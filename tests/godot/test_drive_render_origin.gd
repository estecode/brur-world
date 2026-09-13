extends SceneTree

## Verifies Drive presentation stays local, streamed buildings remain visible, and static meshes do not churn across render cells.
##
## Dependencies:
## - camera_controller.gd owns the Drive render-origin conversion.
## - drive_render_origin_composition.gd owns presentation-only rebasing.
## - main.gd owns production road/background vertical layout.
## - player_vehicle.tscn and gps_route_drive_render_adapter.gd provide production Drive presentation boundaries.

const CameraControllerScript = preload("res://scripts/camera_controller.gd")
const DriveRenderOriginCompositionScript = preload("res://scripts/drive_render_origin_composition.gd")
const GpsRouteDriveRenderAdapterScript = preload("res://scripts/gps_route_drive_render_adapter.gd")
const MainScript = preload("res://scripts/main.gd")
const TEST_WORLD_POSITION := Vector3(52277.0, 0.06, 825907.0)
const MAX_LOCAL_AXIS_M := 512.01
const MIN_DRIVE_DECORATIVE_CLEARANCE_M := 0.25
const MAX_DRIVE_GROUND_DIAMETER_M := 12000.01

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var rig := Node3D.new()
	rig.name = "CameraRig"
	rig.set_script(CameraControllerScript)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	root.add_child(rig)
	await process_frame

	var target := Node3D.new()
	target.position = TEST_WORLD_POSITION
	root.add_child(target)
	rig.call("set_follow_target", target)
	rig.call("set_drive_mode", true)
	await process_frame

	var render_origin: Vector3 = rig.call("get_render_origin_world")
	var target_render: Vector3 = rig.call("world_to_render_position", target.global_position)
	_assert(absf(target_render.x) <= MAX_LOCAL_AXIS_M and absf(target_render.z) <= MAX_LOCAL_AXIS_M, "Drive target stays inside the render-origin cell")
	_assert(Vector2(rig.global_position.x, rig.global_position.z).distance_to(Vector2(target_render.x, target_render.z)) < 0.01, "Drive camera rig uses render-local target coordinates")
	_assert((rig.call("render_to_world_position", target_render) as Vector3).distance_to(target.global_position) < 0.01, "render-to-world conversion reconstructs logical target")
	_assert(camera.near >= 0.25 and camera.near <= 1.0, "Drive near plane stays in local-driving range")
	_assert(camera.far <= 5000.01 and camera.far / camera.near <= 20000.0, "Drive far/near ratio remains bounded")

	var main := MainScript.new() as Node3D
	main.set("camera_rig", rig)
	main.set("current_layer_spacing", float(main.call("_layer_spacing")))
	var road_height := float(main.call("get_road_surface_height"))
	var urban_background_height := float(main.call("_background_height", 3))
	var effective_decorative_height := minf(urban_background_height, -0.20)
	_assert(road_height - effective_decorative_height >= MIN_DRIVE_DECORATIVE_CLEARANCE_M, "Drive physical surface keeps measurable decorative clearance")

	var vehicle_scene := load("res://scenes/player_vehicle.tscn") as PackedScene
	_assert(vehicle_scene != null, "player vehicle scene loads")
	var vehicle := vehicle_scene.instantiate() as Node3D
	root.add_child(vehicle)
	vehicle.call("set_world_position", TEST_WORLD_POSITION)
	vehicle.call("set_heading_rad", 0.73)
	var logical_before := vehicle.global_transform
	vehicle.call("set_render_origin_world", render_origin)
	var visual_root := vehicle.get_node("VisualRoot") as Node3D
	_assert(vehicle.global_transform.is_equal_approx(logical_before), "vehicle logical transform is unchanged by render rebasing")
	_assert(visual_root.top_level, "vehicle visual is detached from the large logical parent transform")
	_assert(visual_root.global_position.distance_to(vehicle.global_position - render_origin) < 0.01, "vehicle visual uses render-local world position")

	var world := Node3D.new()
	var road_leaf := MeshInstance3D.new()
	road_leaf.position = TEST_WORLD_POSITION
	road_leaf.mesh = BoxMesh.new()
	world.add_child(road_leaf)

	var background_leaf := MeshInstance3D.new()
	background_leaf.position = Vector3(0.0, urban_background_height, 0.0)
	var background_mesh := ArrayMesh.new()
	background_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _triangle_arrays(PackedVector3Array([
		TEST_WORLD_POSITION + Vector3(-20.0, 0.0, -20.0),
		TEST_WORLD_POSITION + Vector3(20.0, 0.0, -20.0),
		TEST_WORLD_POSITION + Vector3(0.0, 0.0, 20.0),
	])))
	background_leaf.mesh = background_mesh
	background_leaf.material_override = _transparent_material()
	world.add_child(background_leaf)

	var ground_leaf := MeshInstance3D.new()
	ground_leaf.position = Vector3(TEST_WORLD_POSITION.x, -0.30, TEST_WORLD_POSITION.z)
	var sweden_plane := PlaneMesh.new()
	sweden_plane.size = Vector2(900000.0, 1700000.0)
	ground_leaf.mesh = sweden_plane
	ground_leaf.material_override = _transparent_material()
	world.add_child(ground_leaf)

	var poi := Node3D.new()
	var cloud := Node3D.new()
	var buildings := Node3D.new()
	buildings.position.y = road_height
	root.add_child(buildings)

	var gps_layer := GpsRouteDriveRenderAdapterScript.new()
	gps_layer.player = vehicle
	gps_layer.set("_camera_rig", rig)
	gps_layer.set("_camera", camera)
	var route_renderer := Node3D.new()
	gps_layer.route_renderer = route_renderer

	var composition := DriveRenderOriginCompositionScript.new()
	composition.set("_camera_rig", rig)
	composition.set("_world", world)
	composition.set("_poi_layer", poi)
	composition.set("_cloud_field", cloud)
	composition.set("_building_layer", buildings)
	composition.set("_gps_route_layer", gps_layer)
	composition.call("_connect_building_branch", buildings)
	composition.call("_sync_render_origin")

	var expected_offset := Vector2(-render_origin.x, -render_origin.z)
	_assert(Vector2(poi.position.x, poi.position.z).distance_to(expected_offset) < 0.01, "POI root uses inverse Drive render origin")
	_assert(Vector2(cloud.position.x, cloud.position.z).distance_to(expected_offset) < 0.01, "cloud root uses inverse Drive render origin")
	_assert(Vector2(road_leaf.position.x, road_leaf.position.z).distance_to(Vector2(target_render.x, target_render.z)) < 0.01, "road leaf is render-local")

	var streamed_group := Node3D.new()
	buildings.add_child(streamed_group)
	var streamed_building := MeshInstance3D.new()
	streamed_building.position = TEST_WORLD_POSITION
	streamed_building.mesh = BoxMesh.new()
	streamed_group.add_child(streamed_building)
	_assert(Vector2(streamed_building.position.x, streamed_building.position.z).distance_to(Vector2(target_render.x, target_render.z)) < 0.01, "building chunk added after its viewport group is immediately render-local")
	_assert(absf(streamed_building.position.x) <= MAX_LOCAL_AXIS_M and absf(streamed_building.position.z) <= MAX_LOCAL_AXIS_M, "late-streamed building stays inside Drive render cell")

	_assert(background_leaf.mesh != background_mesh, "Drive replaces canonical BRM2 mesh with render-local mesh")
	var background_bounds := _mesh_vertex_bounds(background_leaf.mesh as ArrayMesh)
	_assert(background_bounds["max_abs_x"] <= MAX_LOCAL_AXIS_M + 20.0 and background_bounds["max_abs_z"] <= MAX_LOCAL_AXIS_M + 20.0, "BRM2 GPU vertices are local at failing coordinate")
	_assert(ground_leaf.mesh is PlaneMesh and ground_leaf.mesh != sweden_plane, "Drive replaces Sweden-scale ocean plane")
	var local_ground := ground_leaf.mesh as PlaneMesh
	_assert(local_ground.size.x <= MAX_DRIVE_GROUND_DIAMETER_M and local_ground.size.y <= MAX_DRIVE_GROUND_DIAMETER_M, "Drive ocean plane has bounded local dimensions")

	var localized_background_before := background_leaf.mesh
	var localized_ground_before := ground_leaf.mesh
	for _frame in range(120):
		composition.call("_sync_render_origin", false)
	_assert(background_leaf.mesh == localized_background_before, "same-cell frames do not rebuild BRM2 geometry")
	_assert(ground_leaf.mesh == localized_ground_before, "same-cell frames do not rebuild ocean geometry")
	_assert(Vector2(streamed_building.position.x, streamed_building.position.z).distance_to(Vector2(target_render.x, target_render.z)) < 0.01, "same-cell frames do not drift streamed buildings")

	for crossing in range(1, 6):
		target.position.x = TEST_WORLD_POSITION.x + float(crossing) * 1100.0
		rig.call("_apply_drive_camera")
		var next_origin: Vector3 = rig.call("get_render_origin_world")
		composition.call("_sync_render_origin", false)
		_assert(background_leaf.mesh == localized_background_before, "render-cell crossing does not copy/rebuild BRM2 mesh")
		var expected_streamed_render := TEST_WORLD_POSITION - next_origin
		_assert(Vector2(streamed_building.position.x, streamed_building.position.z).distance_to(Vector2(expected_streamed_render.x, expected_streamed_render.z)) < 0.01, "streamed building remains stable across repeated render-cell changes")

	rig.call("set_drive_mode", false)
	composition.call("_sync_render_origin", false)
	_assert((rig.call("get_render_origin_world") as Vector3).is_zero_approx(), "Map mode restores zero render origin")
	_assert(Vector2(road_leaf.position.x, road_leaf.position.z).distance_to(Vector2(TEST_WORLD_POSITION.x, TEST_WORLD_POSITION.z)) < 0.01, "Map restores authoritative road coordinates")
	_assert(background_leaf.mesh == background_mesh, "Map restores canonical BRM2 mesh")
	_assert(ground_leaf.mesh == sweden_plane, "Map restores canonical Sweden ocean plane")
	_assert(Vector2(streamed_building.position.x, streamed_building.position.z).distance_to(Vector2(TEST_WORLD_POSITION.x, TEST_WORLD_POSITION.z)) < 0.01, "Map restores streamed building coordinates")
	_assert(route_renderer.position.is_zero_approx(), "Map restores GPS route frame")

	composition.free()
	route_renderer.free()
	gps_layer.free()
	world.free()
	poi.free()
	cloud.free()
	buildings.free()
	vehicle.free()
	main.free()
	target.free()
	rig.free()
	print("godot drive-render-origin tests: OK")
	quit(0)

func _triangle_arrays(vertices: PackedVector3Array) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	return arrays

func _transparent_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return material

func _mesh_vertex_bounds(mesh: ArrayMesh) -> Dictionary:
	var max_abs_x := 0.0
	var max_abs_z := 0.0
	for surface_index in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			max_abs_x = maxf(max_abs_x, absf(vertex.x))
			max_abs_z = maxf(max_abs_z, absf(vertex.z))
	return {"max_abs_x": max_abs_x, "max_abs_z": max_abs_z}

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("drive-render-origin test failed: " + message)
	quit(1)
