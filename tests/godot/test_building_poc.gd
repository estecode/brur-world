extends SceneTree

## Headless contracts for #120 building extrusion, coordinate alignment, and bounded tile streaming.
## Dependencies: production BuildingMeshBuilder, BuildingStreamLayer, and WorldCoordinates only.

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

	var cache_dir := "user://building_poc_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_dir))
	var tile_file := FileAccess.open(cache_dir + "/0_0.jsonl", FileAccess.WRITE)
	_assert(tile_file != null, "test tile cache is writable")
	tile_file.store_line(JSON.stringify(record))
	tile_file.close()

	var coordinates = WorldCoordinatesScript.new(Vector2.ZERO, 100.0)
	var camera := DummyCameraRig.new()
	get_root().add_child(camera)
	var layer := BuildingStreamLayerScript.new()
	layer.cache_dir = cache_dir
	layer.active_radius_tiles = 0
	layer.builds_per_frame = 1
	layer.base_height_m = 0.0
	get_root().add_child(layer)
	layer.setup(coordinates, camera)
	_assert(layer.pending_tile_count() == 1, "visible local tile is queued")
	layer._process(0.0)
	_assert(layer.active_tile_count() == 1, "queued tile becomes one active batched mesh")
	_assert(layer.active_mesh_count() == 1, "one tile does not create one node per building")

	camera.focus = Vector3(150.0, 0.0, -10.0)
	layer._process(0.0)
	_assert(layer.active_tile_count() == 0, "tile outside camera-local radius unloads")

	camera.focus = Vector3(10.0, 0.0, -10.0)
	camera.altitude = 20000.0
	layer._process(0.0)
	_assert(layer.active_tile_count() == 0, "high-altitude map mode keeps 3D building tiles unloaded")

	print("godot building POC tests: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("building POC test failed: " + message)
	quit(1)
