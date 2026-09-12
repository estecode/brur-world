extends SceneTree

## Verifies promoted world-streaming, road/building LOD, building batching, and coordinate contracts.
## Dependencies: production WorldCoordinates, RoadLodPolicy, BuildingLodPolicy, WorldStreamRequest, BuildingMeshBuilder, and BuildingStreamLayer.

const WorldCoordinatesScript = preload("res://scripts/world_coordinates.gd")
const RoadLodPolicyScript = preload("res://scripts/road_lod_policy.gd")
const BuildingLodPolicyScript = preload("res://scripts/building_lod_policy.gd")
const WorldStreamRequestScript = preload("res://scripts/world_stream_request.gd")
const BuildingMeshBuilderScript = preload("res://scripts/building_mesh_builder.gd")
const BuildingStreamLayerScript = preload("res://scripts/building_stream_layer.gd")

var _failed := false

class DummyCameraRig:
	extends Node
	var focus := Vector3(110.0, 0.0, -10.0)
	var altitude := 1000.0
	var view_half_extent_m := 0.0
	func get_focus_world() -> Vector3:
		return focus
	func get_altitude() -> float:
		return altitude
	func get_ground_view_corners() -> PackedVector3Array:
		if view_half_extent_m <= 0.0:
			return PackedVector3Array()
		return PackedVector3Array([
			focus + Vector3(-view_half_extent_m, 0.0, -view_half_extent_m),
			focus + Vector3(view_half_extent_m, 0.0, -view_half_extent_m),
			focus + Vector3(view_half_extent_m, 0.0, view_half_extent_m),
			focus + Vector3(-view_half_extent_m, 0.0, view_half_extent_m),
		])

func _init() -> void:
	_test_coordinate_and_request_contracts()
	_test_road_lod_policy()
	_test_building_identity_and_mesh()
	_test_building_lod_policy()
	_test_bounded_streaming_and_hysteresis()
	_test_camera_view_tile_coverage()
	if _failed:
		quit(1)
		return
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

func _test_road_lod_policy() -> void:
	var motorway_width := RoadLodPolicyScript.road_width_m(0)
	var residential_width := RoadLodPolicyScript.road_width_m(5)
	_assert(is_equal_approx(motorway_width, 24.0), "motorway width stays metre-scale instead of zoom-scale")
	_assert(is_equal_approx(RoadLodPolicyScript.road_width_m(0), motorway_width), "road width is independent of LOD")
	_assert(motorway_width > residential_width, "road classes preserve realistic relative widths")
	_assert(residential_width > RoadLodPolicyScript.road_width_m(6), "local road hierarchy remains monotonic")
	_assert(RoadLodPolicyScript.choose_lod(315000.0, -1) == 0, "far map view selects simplified road LOD")
	_assert(RoadLodPolicyScript.choose_lod(150000.0, -1) == 1, "regional map view selects medium road LOD")
	_assert(RoadLodPolicyScript.choose_lod(43000.0, -1) == 2, "reference map view keeps full road detail")
	_assert(RoadLodPolicyScript.can_build_more(0.0, 0), "build scheduler always allows one pending tile")
	_assert(not RoadLodPolicyScript.can_build_more(0.5, RoadLodPolicyScript.MAX_TILES_PER_FRAME), "road tile builds retain an absolute per-frame cap")

func _test_building_identity_and_mesh() -> void:
	var record := _record(10.0, 10.0, "way/123", 10.0)
	_assert(BuildingMeshBuilderScript.stable_source_id(record) == "way/123", "source identity uses stable source ID")
	_assert(BuildingMeshBuilderScript.stable_seed(record) == BuildingMeshBuilderScript.stable_seed(record.duplicate(true)), "procedural seed survives reload")
	_assert(is_equal_approx(BuildingMeshBuilderScript.height_from_tags({"building:levels": "4"}), 12.0), "building levels derive stable height")
	var mesh: ArrayMesh = BuildingMeshBuilderScript.build_tile_mesh([record], Vector2.ZERO)
	_assert(mesh != null, "building footprint produces a mesh")
	if mesh == null:
		return
	_assert(mesh.get_surface_count() == 1, "one tile batch produces one mesh surface")
	var bounds := mesh.get_aabb()
	_assert(bounds.size.x > 9.9 and bounds.size.z > 9.9, "building footprint keeps metre-scale horizontal bounds")
	_assert(bounds.size.y >= 11.9 and bounds.size.y <= 12.1, "building height is preserved in mesh bounds")

func _test_building_lod_policy() -> void:
	var small := _record(0.0, 0.0, "small", 10.0)
	var medium := _record(0.0, 0.0, "medium", 20.0)
	var large := _record(0.0, 0.0, "large", 40.0)
	var huge := _record(0.0, 0.0, "huge", 70.0)
	_assert(is_equal_approx(BuildingLodPolicyScript.footprint_area_m2(small), 100.0), "building footprint area is derived in square metres")
	var altitudes := [12000.0, 6000.0, 2000.0, 500.0, 50.0]
	var previous_lod := -1
	for altitude in altitudes:
		var lod: int = BuildingLodPolicyScript.choose_lod(altitude)
		_assert(lod >= previous_lod, "zooming in monotonically increases building detail")
		previous_lod = lod
	var records := [small, medium, large, huge]
	_assert(BuildingLodPolicyScript.filter_records(records, BuildingLodPolicyScript.LOD_COARSE).size() == 1, "coarse LOD keeps only very large footprints")
	_assert(BuildingLodPolicyScript.filter_records(records, BuildingLodPolicyScript.LOD_LARGE).size() == 2, "large LOD adds large buildings")
	_assert(BuildingLodPolicyScript.filter_records(records, BuildingLodPolicyScript.LOD_MEDIUM).size() == 3, "medium LOD adds ordinary larger buildings")
	_assert(BuildingLodPolicyScript.filter_records(records, BuildingLodPolicyScript.LOD_FULL).size() == 4, "full LOD includes small buildings")

func _test_bounded_streaming_and_hysteresis() -> void:
	var cache_dir := "user://world_stream_foundation_test_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_dir))
	_write_tile(cache_dir, Vector2i(0, 0), _record(10.0, 10.0, "way/0", 70.0))
	_write_tile(cache_dir, Vector2i(1, 0), _record(110.0, 10.0, "way/1", 70.0))
	_write_tile(cache_dir, Vector2i(2, 0), _record(210.0, 10.0, "way/2", 70.0))
	var coordinates = WorldCoordinatesScript.new(Vector2.ZERO, 100.0)
	var camera := DummyCameraRig.new()
	get_root().add_child(camera)
	var layer := BuildingStreamLayerScript.new()
	layer.active_radius_tiles = 1
	layer.view_margin_tiles = 0
	layer.max_view_radius_tiles = 1
	layer.max_pending_tiles = 2
	layer.builds_per_frame = 1
	layer.build_budget_ms = 1000.0
	layer.prefetch_tiles_ahead = 0
	layer.streaming_enabled = false
	get_root().add_child(layer)
	layer.setup(coordinates, camera, cache_dir)
	_assert(not layer.is_streaming_enabled(), "building streaming can start explicitly disabled")
	_assert(layer.pending_tile_count() == 0 and layer.active_tile_count() == 0, "disabled building streaming performs no tile work")
	layer.set_streaming_enabled(true)
	_assert(layer.is_streaming_enabled(), "building streaming can be enabled explicitly")
	_assert(layer.pending_tile_count() == 2, "pending queue is capped by configured maximum")
	var initial_metrics: Dictionary = layer.consume_perf_metrics()
	_assert(int(initial_metrics["building_dropped_requests"]) >= 1, "overflow requests degrade by dropping optional queued work")
	layer._process(0.0)
	_assert(layer.active_tile_count() == 1, "only one tile builds in one frame")
	layer._process(0.0)
	_assert(layer.active_tile_count() == 2, "second frame advances bounded work")
	layer.set_streaming_enabled(false)
	_assert(layer.active_tile_count() == 0 and layer.pending_tile_count() == 0, "disabling building streaming clears loaded and pending work")
	layer.set_streaming_enabled(true)
	layer._process(0.0)
	_assert(layer.active_tile_count() == 1, "re-enabling building streaming restarts bounded work")
	camera.altitude = 14500.0
	layer._process(0.0)
	_assert(layer.active_tile_count() >= 1, "loaded tiles remain through hysteresis band")
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
	layer.queue_free()
	camera.queue_free()

func _test_camera_view_tile_coverage() -> void:
	var cache_dir := "user://world_stream_view_test_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_dir))
	var coordinates = WorldCoordinatesScript.new(Vector2.ZERO, 100.0)
	var camera := DummyCameraRig.new()
	camera.view_half_extent_m = 120.0
	camera.altitude = 6000.0
	var center := coordinates.world_to_tile(camera.focus)
	for ty in range(center.y - 2, center.y + 3):
		for tx in range(center.x - 2, center.x + 3):
			var tile := Vector2i(tx, ty)
			var origin: Vector2 = coordinates.tile_origin_absolute(tile)
			_write_tile(cache_dir, tile, _record(origin.x + 50.0, origin.y + 50.0, "%d/%d" % [tx, ty], 70.0))
	get_root().add_child(camera)
	var layer := BuildingStreamLayerScript.new()
	layer.active_radius_tiles = 0
	layer.view_margin_tiles = 0
	layer.max_view_radius_tiles = 2
	layer.max_pending_tiles = 25
	layer.builds_per_frame = 1
	layer.build_budget_ms = 1000.0
	layer.prefetch_tiles_ahead = 0
	layer.streaming_enabled = false
	get_root().add_child(layer)
	layer.setup(coordinates, camera, cache_dir)
	layer.set_streaming_enabled(true)
	var snapshot: Dictionary = layer.debug_snapshot()
	_assert(int(snapshot["wanted_tiles"]) == 25, "camera ground extent requests multiple visible tiles instead of one centered tile")
	_assert(int(snapshot["view_radius_tiles"]) == 2, "camera-driven tile radius is bounded by the production cap")
	_assert(int(snapshot["building_lod"]) == BuildingLodPolicyScript.LOD_LARGE, "streaming uses altitude-selected building LOD")
	_assert(layer.pending_tile_count() == 25, "bounded visible tile set is queued deterministically")
	camera.view_half_extent_m = 10000.0
	camera.focus += Vector3(101.0, 0.0, 0.0)
	layer._process(0.0)
	snapshot = layer.debug_snapshot()
	_assert(int(snapshot["view_radius_tiles"]) == 2, "huge camera extent cannot exceed configured tile radius")
	_assert(int(snapshot["wanted_tiles"]) <= 25, "streaming work remains bounded at extreme view extents")
	layer.set_streaming_enabled(false)
	_assert(layer.active_tile_count() == 0 and layer.pending_tile_count() == 0, "multi-tile stream still clears completely when HUS turns off")
	layer.queue_free()
	camera.queue_free()

func _record(x: float, y: float, source_id: String, size_m: float = 10.0) -> Dictionary:
	var half := size_m * 0.5
	return {"id": source_id, "x": x, "y": y, "geometry": [{"outer": [[x - half, y - half], [x + half, y - half], [x + half, y + half], [x - half, y + half]], "holes": []}], "tags": {"building": "yes", "building:levels": "4"}}

func _write_tile(cache_dir: String, tile: Vector2i, record: Dictionary) -> void:
	var path := "%s/%d_%d.jsonl" % [cache_dir, tile.x, tile.y]
	var file := FileAccess.open(path, FileAccess.WRITE)
	_assert(file != null, "test tile is writable")
	if file == null:
		return
	file.store_line(JSON.stringify(record))
	file.close()

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("world streaming foundation test failed: " + message)
