extends SceneTree

## Verifies building viewport requests stay stable across chunk-edge jitter and Drive heading changes covered by the retained margin.
## Dependencies: production BuildingStreamLayer, BuildingLodPolicy, and WorldCoordinates with tiny BMC fixture chunks.

const BuildingStreamLayerScript = preload("res://scripts/building_stream_layer.gd")
const BuildingLodPolicyScript = preload("res://scripts/building_lod_policy.gd")
const WorldCoordinatesScript = preload("res://scripts/world_coordinates.gd")

var _failed := false

class DummyCameraRig:
	extends Node
	var focus := Vector3.ZERO
	var altitude := 50.0
	var view_half_extent_m := 250.0
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

class DriveCameraRig:
	extends Node
	var focus := Vector3.ZERO
	var altitude := 12.0
	var heading := 0.0
	var side_extent_m := 1500.0
	var forward_extent_m := 4500.0
	var streaming_radius_m := 5000.0
	func get_focus_world() -> Vector3:
		return focus
	func get_altitude() -> float:
		return altitude
	func is_driving_view() -> bool:
		return true
	func get_streaming_ground_radius_m() -> float:
		return streaming_radius_m
	func get_ground_view_corners() -> PackedVector3Array:
		var basis := Basis(Vector3.UP, heading)
		var points := PackedVector3Array()
		for local in [
			Vector3(-side_extent_m, 0.0, -forward_extent_m),
			Vector3(side_extent_m, 0.0, -forward_extent_m),
			Vector3(side_extent_m, 0.0, forward_extent_m),
			Vector3(-side_extent_m, 0.0, forward_extent_m),
		]:
			points.append(focus + basis * local)
		return points

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var directory := "user://building_hysteresis_%d" % Time.get_ticks_usec()
	_write_grid(directory, BuildingLodPolicyScript.LOD_FULL, 8)
	var coordinates = WorldCoordinatesScript.new(Vector2.ZERO, 2000.0)
	await _test_chunk_edge_hysteresis(directory, coordinates)
	await _test_drive_heading_hysteresis(directory, coordinates)
	if _failed:
		quit(1)
		return
	print("godot building-viewport-hysteresis tests: OK")
	quit(0)

func _test_chunk_edge_hysteresis(directory: String, coordinates) -> void:
	var camera := DummyCameraRig.new()
	camera.focus = Vector3(1745.0, 0.0, 0.0)
	root.add_child(camera)
	var layer := BuildingStreamLayerScript.new()
	layer.view_margin_chunks = 1
	layer.max_view_chunks = 64
	layer.streaming_enabled = false
	root.add_child(layer)
	layer.setup(coordinates, camera, directory)
	layer.set_streaming_enabled(true)
	await _wait_until_ready(layer, 240)
	_assert(layer.is_viewport_ready(), "initial sticky viewport becomes ready")
	var initial: Dictionary = layer.debug_snapshot()
	var signature := String(initial["desired_signature"])
	var generation := int(initial["request_generation"])
	var initial_meshes := _active_meshes_by_key(layer)

	# 1745 -> 1755 m makes the core viewport cross the x=2000 m chunk edge.
	# The already requested one-chunk margin covers both core bounds, so a stable
	# streamer must not cancel/restart its viewport on every oscillation.
	for index in range(60):
		camera.focus.x = 1745.0 if index % 2 == 0 else 1755.0
		layer._process(0.0)
		await process_frame
		var snapshot: Dictionary = layer.debug_snapshot()
		_assert(String(snapshot["desired_signature"]) == signature, "chunk-edge jitter keeps the retained desired signature")
		_assert(int(snapshot["request_generation"]) == generation, "chunk-edge jitter does not restart building staging")
		_assert(layer.is_viewport_ready(), "chunk-edge jitter keeps the published viewport ready")

	# Move the core into chunk x=2. This leaves the retained x=-1..1 viewport,
	# forcing a new x=1..3 request while deliberately retaining x=1 overlap so
	# resource identity across a genuine atomic viewport swap can be asserted.
	camera.focus.x = 4250.0
	layer._process(0.0)
	var moved: Dictionary = layer.debug_snapshot()
	_assert(String(moved["desired_signature"]) != signature, "leaving the retained margin requests a new viewport")
	_assert(int(moved["request_generation"]) > generation, "real viewport movement advances the request generation")
	await _wait_until_ready(layer, 240)
	_assert(layer.is_viewport_ready(), "moved viewport becomes ready")
	var moved_meshes := _active_meshes_by_key(layer)
	var overlap := 0
	for key_value in initial_meshes.keys():
		var key := String(key_value)
		if not moved_meshes.has(key):
			continue
		overlap += 1
		_assert(moved_meshes[key] == initial_meshes[key], "overlapping viewport chunks reuse the exact uploaded ArrayMesh resource")
	_assert(overlap > 0, "viewport movement fixture retains overlapping building chunks")
	var metrics: Dictionary = layer.consume_perf_metrics()
	_assert(int(metrics.get("building_mesh_reuses", 0)) >= overlap, "viewport movement records mesh-resource reuse for overlapping chunks")
	layer.queue_free()
	camera.queue_free()
	await process_frame

func _test_drive_heading_hysteresis(directory: String, coordinates) -> void:
	var camera := DriveCameraRig.new()
	camera.focus = Vector3.ZERO
	root.add_child(camera)
	var layer := BuildingStreamLayerScript.new()
	layer.view_margin_chunks = 1
	layer.max_view_chunks = 64
	layer.streaming_enabled = false
	root.add_child(layer)
	layer.setup(coordinates, camera, directory)
	layer.set_streaming_enabled(true)
	await _wait_until_ready(layer, 240)
	_assert(layer.is_viewport_ready(), "Drive viewport becomes ready")
	var initial: Dictionary = layer.debug_snapshot()
	var signature := String(initial["desired_signature"])
	var generation := int(initial["request_generation"])
	_assert(int(initial["coverage_chunks"]) <= layer.max_view_chunks, "Drive rotation-invariant coverage stays within configured chunk budget")

	# Raw Drive frustum corners rotate, but the explicit streaming radius does not.
	# Heading and visual transition geometry therefore cannot invalidate building
	# staging while the authoritative focus remains inside the retained viewport.
	for index in range(72):
		camera.heading = TAU * float(index) / 72.0
		layer._process(0.0)
		await process_frame
		var snapshot: Dictionary = layer.debug_snapshot()
		_assert(String(snapshot["desired_signature"]) == signature, "Drive heading changes keep one building viewport signature")
		_assert(int(snapshot["request_generation"]) == generation, "Drive heading changes do not restart building staging")
		_assert(layer.is_viewport_ready(), "Drive heading changes keep buildings ready")

	layer.queue_free()
	camera.queue_free()
	await process_frame

func _active_meshes_by_key(layer: Node) -> Dictionary:
	var result: Dictionary = {}
	var active_group := layer.get("_active_group") as Node3D
	if active_group == null:
		return result
	for child_value in active_group.get_children():
		var instance := child_value as MeshInstance3D
		if instance == null or not instance.mesh is ArrayMesh:
			continue
		var key := String(instance.get_meta(&"brur_building_chunk_key", ""))
		if not key.is_empty():
			result[key] = instance.mesh
	return result

func _wait_until_ready(layer: Node, max_frames: int) -> void:
	for _index in range(max_frames):
		layer._process(0.0)
		if layer.is_viewport_ready():
			return
		await process_frame
	_assert(false, "building viewport becomes ready within bounded fixture frames")

func _write_grid(root_dir: String, lod: int, radius: int) -> void:
	var directory := "%s/lod%d" % [root_dir, lod]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			_write_bmc("%s/%d_%d.bmc" % [directory, x, y])

func _write_bmc(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_assert(file != null, "fixture BMC chunk is writable")
	if file == null:
		return
	file.store_buffer("BMC2".to_ascii_buffer())
	file.store_32(2)
	file.store_32(3)
	file.store_float(0.0)
	file.store_float(0.0)
	file.store_32(3)
	for position in [Vector3(0.0, 0.0, 0.0), Vector3(20.0, 0.0, 0.0), Vector3(0.0, 12.0, -20.0)]:
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

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("building-viewport-hysteresis test failed: " + message)