extends SceneTree

## Headless contracts for #122 building identity, coordinate alignment, bounded streaming, and LOD hysteresis.
## Dependencies: production BuildingMeshBuilder, BuildingStreamLayer, WorldCoordinates, and WorldStreamRequest only.

const BuildingMeshBuilderScript = preload("res://scripts/building_mesh_builder.gd")
const BuildingStreamLayerScript = preload("res://scripts/building_stream_layer.gd")
const WorldCoordinatesScript = preload("res://scripts/world_coordinates.gd")

class DummyCameraRig:
	extends Node
	var focus := Vector3(10.0, 0.0, -10.0)
	var altitude := 1000.0
	func get_focus_world() -> Vector3:
		return focus
	func get_altitude() -> float:
		return altitude

func _init() -> void:
	var record := {
		"id": "way/123",
		"x": 10.0,
		"y": 10.0,
		"geometry": [{"outer": [[5.0, 5.0], [15.0, 5.0], [15.0, 15.0], [5.0, 15.0]], "holes": []}],
		"tags": {"building": "yes", "building:levels": "4"},
	}
	var mesh: ArrayMesh = BuildingMeshBuilderScript.build_tile_mesh([record], Vector2.ZERO)
	_assert(mesh != null, "square footprint produces a mesh")
	_assert(mesh.get_surface_count() == 1, "tile batch is one mesh surface")
	var bounds := mesh.get_aabb()
	_assert(bounds.size.x > 9.9 and bounds.size.z > 9.9, "footprint keeps meter-scale horizontal bounds")
	_assert(bounds.size.y >= 11.9 and bounds.size.y <= 12.1, "building:levels produces expected 12 m height")
	_assert(is_equal_approx(BuildingMeshBuilderScript.height_from_tags({"height": "18 m"}), 18.0), "explicit height is parsed")
	_assert(BuildingMeshBuilderScript.stable_source_id(record) == "way/123", "source identity uses stable exported id")
	_assert(BuildingMeshBuilderScript.stable_seed(record) == BuildingMeshBuilderScript.stable_seed(record), "procedural seed is deterministic")

	var coordinates = WorldCoordinatesScript.new(Vector2.ZERO, 100.0)
	_assert(coordinates.tile_identity(Vector2i(1, 2)) == "1:2", "tile identity is deterministic")
	_assert(coordinates.world_tile_identity(Vector3(150.0, 0.0, -250.0)) == "1:2", "world position uses shared tile identity")
	_assert(coordinates.absolute_tile_identity(Vector2(150.0, 250.0)) == "1:2", "absolute position uses same tile identity")

	var cache_dir := "user://building_poc_test_122"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_dir))
	_write_tile(cache_dir, Vector2i(0, 0), record)
	_write_tile(cache_dir, Vector2i(1, 0), _offset_record(record, 110.0, 10.0, "way/124"))
	_write_tile(cache_dir, Vector2i(2, 0), _offset_record(record, 210.0, 10.0, "way/125"))

	var camera := DummyCameraRig.new()
	get_root().add_child(camera)
	var layer := BuildingStreamLayerScript.new()
	layer.cache_dir = cache_dir
	layer.active_radius_tiles = 0
	layer.prefetch_tiles_ahead = 1
	layer.builds_per_frame = 1
	layer.max_pending_tiles = 1
	layer.base_height_m = 0.0
	get_root().add_child(layer)
	layer.setup(coordinates, camera)
	_assert(layer.pending_tile_count() == 1, "visible local tile is queued")
	_assert(layer.tile_state(Vector2i(0, 0)) == "requested", "tile lifecycle begins requested")
	layer._process(0.0)
	_assert(layer.active_tile_count() == 1, "queued tile becomes one active batched mesh")
	_assert(layer.active_mesh_count() == 1, "one tile does not create one node per building")
	_assert(layer.tile_state(Vector2i(0, 0)) == "visible", "tile lifecycle reaches visible")

	camera.focus = Vector3(110.0, 0.0, -10.0)
	layer._process(0.0)
	_assert(layer.active_tile_count() <= 1, "large move unloads old tile before unbounded growth")
	_assert(layer.pending_tile_count() <= 1, "pending queue obeys configured cap")
	layer._process(0.0)
	_assert(layer.tile_state(Vector2i(1, 0)) == "visible", "new local tile becomes visible after move")

	camera.altitude = 14500.0
	layer._process(0.0)
	_assert(layer.active_tile_count() == 1, "LOD hysteresis keeps buildings visible between thresholds")
	camera.altitude = 15100.0
	layer._process(0.0)
	_assert(layer.active_tile_count() == 0, "hide threshold unloads building tiles")
	camera.altitude = 14500.0
	layer._process(0.0)
	_assert(layer.active_tile_count() == 0, "hysteresis prevents immediate re-entry below hide threshold")
	camera.altitude = 13900.0
	layer._process(0.0)
	_assert(layer.pending_tile_count() == 1, "appear threshold requests tiles again")
	layer._process(0.0)
	_assert(layer.active_tile_count() == 1, "tiles rebuild after re-entry")

	for x in [10.0, 110.0, 210.0, 10.0]:
		camera.focus = Vector3(x, 0.0, -10.0)
		layer._process(0.0)
		layer._process(0.0)
		_assert(layer.active_tile_count() <= 1, "stress jumps keep active mesh count bounded")
		_assert(layer.pending_tile_count() <= 1, "stress jumps keep pending queue bounded")

	var snapshot: Dictionary = layer.debug_snapshot()
	_assert(int(snapshot.get("active_records", 0)) <= 1, "debug instrumentation reports bounded active records")
	var metrics: Dictionary = layer.consume_perf_metrics()
	_assert(metrics.has("building_build_max_ms"), "streaming metrics include build timing")
	_assert(metrics.has("building_dropped_requests"), "streaming metrics include graceful-degradation drops")

	print("godot building/world streaming POC tests: OK")
	quit(0)

func _write_tile(cache_dir: String, tile: Vector2i, record: Dictionary) -> void:
	var tile_file := FileAccess.open("%s/%d_%d.jsonl" % [cache_dir, tile.x, tile.y], FileAccess.WRITE)
	_assert(tile_file != null, "test tile cache is writable")
	tile_file.store_line(JSON.stringify(record))
	tile_file.close()

func _offset_record(source: Dictionary, x: float, y: float, source_id: String) -> Dictionary:
	var result := source.duplicate(true)
	result["id"] = source_id
	result["x"] = x
	result["y"] = y
	var outer := []
	for point in source["geometry"][0]["outer"]:
		outer.append([float(point[0]) + x - 10.0, float(point[1]) + y - 10.0])
	result["geometry"][0]["outer"] = outer
	return result

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("building/world streaming POC test failed: " + message)
	quit(1)
