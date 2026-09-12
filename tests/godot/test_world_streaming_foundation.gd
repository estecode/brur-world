extends SceneTree

## Verifies world coordinates, road/building LOD policy, prebuilt chunk decoding, and atomic building viewport staging.
## Dependencies: production WorldCoordinates, RoadLodPolicy, BuildingLodPolicy, BuildingMeshChunkCodec, BuildingMeshBuilder, and BuildingStreamLayer.

const WorldCoordinatesScript = preload("res://scripts/world_coordinates.gd")
const RoadLodPolicyScript = preload("res://scripts/road_lod_policy.gd")
const BuildingLodPolicyScript = preload("res://scripts/building_lod_policy.gd")
const BuildingMeshChunkCodecScript = preload("res://scripts/building_mesh_chunk_codec.gd")
const BuildingMeshBuilderScript = preload("res://scripts/building_mesh_builder.gd")
const BuildingStreamLayerScript = preload("res://scripts/building_stream_layer.gd")

var _failed := false

class DummyCameraRig:
	extends Node
	var focus := Vector3.ZERO
	var altitude := 6000.0
	var view_half_extent_m := 9000.0
	func get_focus_world() -> Vector3:
		return focus
	func get_altitude() -> float:
		return altitude
	func get_ground_view_corners() -> PackedVector3Array:
		return PackedVector3Array([
			focus + Vector3(-view_half_extent_m, 0.0, -view_half_extent_m),
			focus + Vector3(view_half_extent_m, 0.0, -view_half_extent_m),
			focus + Vector3(view_half_extent_m, 0.0, view_half_extent_m),
			focus + Vector3(-view_half_extent_m, 0.0, view_half_extent_m),
		])

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_coordinate_contracts()
	_test_road_lod_policy()
	_test_building_identity_and_mesh()
	_test_building_lod_policy()
	_test_chunk_codec()
	await _test_atomic_viewport_staging_and_cache()
	if _failed:
		quit(1)
		return
	print("world streaming foundation tests: OK")
	quit(0)

func _test_coordinate_contracts() -> void:
	var coordinates = WorldCoordinatesScript.new(Vector2.ZERO, 32000.0)
	var malmo := Vector2(1447576.394, 7480180.846)
	var goteborg := Vector2(1319000.0, 7769000.0)
	var stockholm := Vector2(2013000.0, 8251000.0)
	var malmo_id := coordinates.absolute_tile_identity(malmo)
	_assert(malmo_id == coordinates.absolute_tile_identity(malmo), "tile identity is deterministic")
	_assert(malmo_id != coordinates.absolute_tile_identity(goteborg), "Malmö and Göteborg resolve to different tile identities")
	_assert(malmo_id != coordinates.absolute_tile_identity(stockholm), "Malmö and Stockholm resolve to different tile identities")
	var world: Vector3 = coordinates.absolute_to_world(stockholm)
	_assert(coordinates.world_to_absolute(world).is_equal_approx(stockholm), "absolute/world conversion round-trips through one owner")

func _test_road_lod_policy() -> void:
	var motorway_width := RoadLodPolicyScript.road_width_m(0)
	var residential_width := RoadLodPolicyScript.road_width_m(5)
	_assert(is_equal_approx(motorway_width, 24.0), "motorway width stays metre-scale")
	_assert(motorway_width > residential_width, "road class hierarchy remains monotonic")
	_assert(RoadLodPolicyScript.choose_lod(315000.0, -1) == 0, "far map view selects simplified road LOD")
	_assert(RoadLodPolicyScript.choose_lod(43000.0, -1) == 2, "reference map view keeps full road detail")

func _test_building_identity_and_mesh() -> void:
	var record := _record(10.0, 10.0, "way/123", 10.0)
	_assert(BuildingMeshBuilderScript.stable_source_id(record) == "way/123", "source identity uses stable source ID")
	_assert(is_equal_approx(BuildingMeshBuilderScript.height_from_tags({"building:levels": "4"}), 12.0), "building height reference remains stable")
	var mesh: ArrayMesh = BuildingMeshBuilderScript.build_tile_mesh([record], Vector2.ZERO)
	_assert(mesh != null and mesh.get_surface_count() == 1, "offline/reference building mesh builder still emits one batch")

func _test_building_lod_policy() -> void:
	var small := _record(0.0, 0.0, "small", 10.0)
	var medium := _record(0.0, 0.0, "medium", 20.0)
	var large := _record(0.0, 0.0, "large", 40.0)
	var huge := _record(0.0, 0.0, "huge", 70.0)
	var records := [small, medium, large, huge]
	_assert(BuildingLodPolicyScript.filter_records(records, BuildingLodPolicyScript.LOD_COARSE).size() == 1, "coarse LOD keeps only very large footprints")
	_assert(BuildingLodPolicyScript.filter_records(records, BuildingLodPolicyScript.LOD_LARGE).size() == 2, "large LOD adds large buildings")
	_assert(BuildingLodPolicyScript.filter_records(records, BuildingLodPolicyScript.LOD_MEDIUM).size() == 3, "medium LOD adds ordinary larger buildings")
	_assert(BuildingLodPolicyScript.filter_records(records, BuildingLodPolicyScript.LOD_FULL).size() == 4, "full LOD includes small buildings")
	_assert(BuildingLodPolicyScript.chunk_size_m(0) > BuildingLodPolicyScript.chunk_size_m(1), "coarse spatial chunks are larger")
	_assert(BuildingLodPolicyScript.chunk_size_m(1) > BuildingLodPolicyScript.chunk_size_m(2), "LOD pyramid spatial scale decreases monotonically")
	_assert(BuildingLodPolicyScript.chunk_size_m(2) > BuildingLodPolicyScript.chunk_size_m(3), "full detail uses the smallest chunks")

func _test_chunk_codec() -> void:
	var directory := "user://building_codec_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := "%s/test.bmc" % directory
	_write_bmc(path, 3)
	var decoded: Dictionary = BuildingMeshChunkCodecScript.decode_file(path)
	_assert(bool(decoded.get("ok", false)), "prebuilt BMC1 chunk decodes")
	_assert(int(decoded.get("vertices", 0)) == 3, "prebuilt chunk preserves vertex count")
	var arrays := BuildingMeshChunkCodecScript.arrays_for_mesh(decoded)
	_assert((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == 3, "decoded positions are mesh-ready without triangulation")

func _test_atomic_viewport_staging_and_cache() -> void:
	var directory := "user://building_atomic_%d" % Time.get_ticks_usec()
	var coordinates = WorldCoordinatesScript.new(Vector2.ZERO, 2000.0)
	_write_lod_grid(directory, 1, Vector2i.ZERO, 3)
	_write_lod_grid(directory, 1, Vector2i(4, 0), 3)
	var camera := DummyCameraRig.new()
	camera.focus = Vector3.ZERO
	camera.altitude = 6000.0
	camera.view_half_extent_m = 7000.0
	get_root().add_child(camera)
	var layer := BuildingStreamLayerScript.new()
	layer.view_margin_chunks = 0
	layer.max_view_chunks = 64
	layer.max_cache_chunks = 6
	layer.streaming_enabled = false
	get_root().add_child(layer)
	layer.setup(coordinates, camera, directory)
	_assert(not layer.is_streaming_enabled(), "HUS can start with zero building streaming work")
	_assert(layer.active_mesh_count() == 0, "disabled HUS has no presentation mesh")

	layer.set_streaming_enabled(true)
	await _wait_until_ready(layer, 120)
	_assert(layer.is_viewport_ready(), "complete first viewport becomes ready")
	var first_snapshot: Dictionary = layer.debug_snapshot()
	var first_signature := String(first_snapshot["active_signature"])
	_assert(int(first_snapshot["active_chunks"]) > 1, "one atomic viewport mesh can be composed from multiple chunks")
	_assert(layer.active_mesh_count() == 1, "multiple source chunks publish as one coherent mesh")

	camera.focus = Vector3(32000.0, 0.0, 0.0)
	layer._process(0.0)
	var during: Dictionary = layer.debug_snapshot()
	_assert(String(during["active_signature"]) == first_signature, "old complete viewport remains visible while replacement stages")
	_assert(layer.active_mesh_count() == 1, "staging never clears the previous coherent presentation")
	await _wait_until_ready(layer, 120)
	var second_snapshot: Dictionary = layer.debug_snapshot()
	_assert(String(second_snapshot["active_signature"]) != first_signature, "replacement viewport publishes after complete readiness")
	_assert(layer.active_mesh_count() == 1, "atomic replacement remains one presentation mesh")

	camera.focus = Vector3.ZERO
	layer._process(0.0)
	await _wait_until_ready(layer, 120)
	var metrics: Dictionary = layer.consume_perf_metrics()
	_assert(int(metrics["building_cache_hits"]) > 0, "recent viewport chunks are reused from bounded cache")
	_assert(int(layer.debug_snapshot()["cache_chunks"]) <= layer.max_cache_chunks, "decoded chunk cache stays explicitly bounded")

	# Rapidly supersede one request before its result is polled; only the latest generation may publish.
	camera.focus = Vector3(32000.0, 0.0, 0.0)
	layer._process(0.0)
	camera.focus = Vector3.ZERO
	layer._update_desired_request(false)
	await _wait_until_ready(layer, 120)
	_assert(String(layer.debug_snapshot()["active_signature"]) == String(layer.debug_snapshot()["desired_signature"]), "stale staging cannot publish over the latest camera request")

	layer.set_streaming_enabled(false)
	_assert(layer.active_mesh_count() == 0, "HUS OFF clears the complete building presentation immediately")
	_assert(not bool(layer.debug_snapshot()["stage_in_flight"]) or not layer.is_viewport_ready(), "HUS OFF never reports a ready streamed viewport")
	layer.queue_free()
	camera.queue_free()
	await process_frame

func _wait_until_ready(layer: Node, max_frames: int) -> void:
	for _index in range(max_frames):
		layer._process(0.0)
		if layer.is_viewport_ready():
			return
		await process_frame
	_assert(false, "building viewport staging completed within bounded test frames")

func _write_lod_grid(root_dir: String, lod: int, center: Vector2i, radius: int) -> void:
	var directory := "%s/lod%d" % [root_dir, lod]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			_write_bmc("%s/%d_%d.bmc" % [directory, x, y], 3)

func _write_bmc(path: String, vertex_count: int) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_assert(file != null, "test BMC chunk is writable")
	if file == null:
		return
	file.store_buffer("BMC1".to_ascii_buffer())
	file.store_32(1)
	file.store_32(vertex_count)
	var positions := [Vector3(0.0, 0.0, 0.0), Vector3(20.0, 0.0, 0.0), Vector3(0.0, 12.0, -20.0)]
	for index in range(vertex_count):
		var position: Vector3 = positions[index % positions.size()]
		file.store_float(position.x)
		file.store_float(position.y)
		file.store_float(position.z)
		file.store_float(0.0)
		file.store_float(1.0)
		file.store_float(0.0)
		file.store_8(128)
		file.store_8(132)
		file.store_8(136)
		file.store_8(255)
	file.close()

func _record(x: float, y: float, source_id: String, size_m: float = 10.0) -> Dictionary:
	var half := size_m * 0.5
	return {"id": source_id, "x": x, "y": y, "geometry": [{"outer": [[x - half, y - half], [x + half, y - half], [x + half, y + half], [x - half, y + half]], "holes": []}], "tags": {"building": "yes", "building:levels": "4"}}

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("world streaming foundation test failed: " + message)
