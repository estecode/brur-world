extends SceneTree

## Verifies the promoted world-streaming, building batching, and coordinate contracts.
## Dependencies: production WorldCoordinates, WorldStreamRequest, BuildingMeshBuilder, and BuildingStreamLayer.

const WorldCoordinatesScript = preload("res://scripts/world_coordinates.gd")
const WorldStreamRequestScript = preload("res://scripts/world_stream_request.gd")
const BuildingMeshBuilderScript = preload("res://scripts/building_mesh_builder.gd")
const BuildingStreamLayerScript = preload("res://scripts/building_stream_layer.gd")

class DummyCameraRig:
	extends Node
	var focus := Vector3(110.0, 0.0, -10.0)
	var altitude := 1000.0
	func get_focus_world() -> Vector3:
		return focus
	func get_altitude() -> float:
		return altitude

func _init() -> void:
	_test_coordinate_and_request_contracts()
	_test_building_identity_and_mesh()
	_test_bounded_streaming_and_hysteresis()
	print("world streaming foundation tests: OK")
	quit(0)

func _test_coordinate_and_request_contracts() -> void:
	var coordinates = WorldCoordinatesScript.new(Vector2.ZERO, 32000.0)
	var malmo := Vector2(1447576.394, 7480180.846)
	var goteborg := Vector2(1319000.0, 7769000.0)
	var stockholm := Vector2(2013000.0, 8251000.0)
	var malmo_id := coordinates.absolute_tile_identity(malmo)
	_assert(malmo_id == coordinates.absolute_tile_identity(malmo), "tile identity is deterministic")
	_assert(malmo_id != coordinates.absolute_tile_identity(goteborg), "Malmö and Göteborg resolve to different tile identities")
	_assert(malmo_id != coordinates.absolute_tile_identity(stockholm), "Malmö and Stockholm resolve to different tile identities")
	var malmo_world: Vector3 = coordinates.absolute_to_world(malmo)
	_assert(coordinates.world_tile_identity(malmo_world) == malmo_id, "absolute and world positions share one tile identity owner")

	var request = WorldStreamRequestScript.new(Vector3(1.0, 2.0, 3.0), 4500.0, Vector3(4.0, 9.0, -6.0))
	_assert(request.focus_world == Vector3(1.0, 2.0, 3.0), "stream request preserves focus")
	_assert(is_equal_approx(request.altitude_m, 4500.0), "stream request preserves altitude")
	_assert(request.horizontal_motion() == Vector2(4.0, -6.0), "stream request exposes horizontal motion without presentation policy")

func _test_building_identity_and_mesh() -> void:
	var record := _record(10.0, 10.0, "way/123")
	_assert(BuildingMeshBuilderScript.stable_source_id(record) == "way/123", "source identity uses stable source ID")
	_assert(BuildingMeshBuilderScript.stable_seed(record) == BuildingMeshBuilderScript.stable_seed(record.duplicate(true)), "procedural seed survives reload")
	_assert(is_equal_approx(BuildingMeshBuilderScript.height_from_tags({"building:levels": "4"}), 12.0), "building levels derive stable height")
	var mesh: ArrayMesh = BuildingMeshBuilderScript.build_tile_mesh([record], Vector2.ZERO)
	_assert(mesh != null, "building footprint produces a mesh")
	_assert(mesh.get_surface_count() == 1, "one tile batch produces one mesh surface")
	var bounds := mesh.get_aabb()
	_assert(bounds.size.x > 9.9 and bounds.size.z > 9.9, "building footprint keeps metre-scale horizontal bounds")
	_assert(bounds.size.y >= 11.9 and bounds.size.y <= 12.1, "building height is preserved in mesh bounds")

func _test_bounded_streaming_and_hysteresis() -> void:
	var cache_dir := "user://world_stream_foundation_test_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_dir))
	_write_tile(cache_dir, Vector2i(0, 0), _record(10.0, 10.0, "way/0"))
	_write_tile(cache_dir, Vector2i(1, 0), _record(110.0, 10.0, "way/1"))
	_write_tile(cache_dir, Vector2i(2, 0), _record(210.0, 10.0, "way/2"))

	var coordinates = WorldCoordinatesScript.new(Vector2.ZERO, 100.0)
	var camera := DummyCameraRig.new()
	get_root().add_child(camera)
	var layer := BuildingStreamLayerScript.new()
	layer.active_radius_tiles = 1
	layer.max_pending_tiles = 2
	layer.builds_per_frame = 1
	layer.build_budget_ms = 1000.0
	layer.prefetch_tiles_ahead = 0
	get_root().add_child(layer)
	layer.setup(coordinates, camera, cache_dir)

	_assert(layer.pending_tile_count() == 2, "pending queue is capped by configured maximum")
	var initial_metrics: Dictionary = layer.consume_perf_metrics()
	_assert(int(initial_metrics["building_dropped_requests"]) >= 1, "overflow requests degrade by dropping optional queued work")
	layer._process(0.0)
	_assert(layer.active_tile_count() == 1, "only one tile builds in one frame")
	_assert(layer.pending_tile_count() == 1, "remaining work stays queued")
	layer._process(0.0)
	_assert(layer.active_tile_count() == 2, "second frame advances bounded work")
	_assert(layer.pending_tile_count() == 0, "bounded queue drains across frames")

	camera.altitude = 14500.0
	layer._process(0.0)
	_assert(layer.active_tile_count() == 2, "loaded tiles remain through hysteresis band")
	camera.altitude = 15100.0
	layer._process(0.0)
	_assert(layer.active_tile_count() == 0, "tiles unload above hide threshold")
	camera.altitude = 14500.0
	layer._process(0.0)
	_assert(layer.active_tile_count() == 0, "hidden layer does not flap back on inside hysteresis band")

	camera.altitude = 1000.0
	layer._process(0.0)
	_assert(layer.active_tile_count() == 1, "layer can reload after becoming visible again")
	camera.focus = Vector3(1000.0, 0.0, -10.0)
	layer._process(0.0)
	_assert(layer.active_tile_count() == 0, "large location jump unloads old geometry")
	_assert(layer.pending_tile_count() == 0, "large location jump does not leave stale queued tiles")

	for _cycle in range(3):
		camera.focus = Vector3(110.0, 0.0, -10.0)
		layer._process(0.0)
		_assert(layer.active_tile_count() == 1, "stress reload activates bounded geometry")
		camera.focus = Vector3(1000.0, 0.0, -10.0)
		layer._process(0.0)
		_assert(layer.active_tile_count() == 0, "stress unload clears old geometry")
	_assert(layer.debug_snapshot()["active_records"] == 0, "repeated unload cycles leave no active record leak")

func _record(x: float, y: float, source_id: String) -> Dictionary:
	return {
		"id": source_id,
		"x": x,
		"y": y,
		"geometry": [{"outer": [[x - 5.0, y - 5.0], [x + 5.0, y - 5.0], [x + 5.0, y + 5.0], [x - 5.0, y + 5.0]], "holes": []}],
		"tags": {"building": "yes", "building:levels": "4"},
	}

func _write_tile(cache_dir: String, tile: Vector2i, record: Dictionary) -> void:
	var path := "%s/%d_%d.jsonl" % [cache_dir, tile.x, tile.y]
	var file := FileAccess.open(path, FileAccess.WRITE)
	_assert(file != null, "test tile is writable")
	file.store_line(JSON.stringify(record))
	file.close()

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("world streaming foundation test failed: " + message)
	quit(1)
