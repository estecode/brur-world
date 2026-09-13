extends SceneTree

## Verifies Drive presentation uses bounded GPU-facing coordinates and measurable depth margins at the prior failing Sweden location.
##
## Dependencies:
## - camera_controller.gd owns the presentation-only Drive render-origin conversion.
## - drive_render_origin_composition.gd localizes road/building transforms plus transparent BRM2/ocean mesh geometry.
## - main.gd owns the production road/background vertical layout used for clearance measurement.
## - player_vehicle.tscn uses Vehicle's VisualRoot adapter without moving logical vehicle state.
## - gps_route_drive_render_adapter.gd rebases route presentation and converts Drive picking back to logical world coordinates.

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
	_assert(absf(target_render.x) <= MAX_LOCAL_AXIS_M and absf(target_render.z) <= MAX_LOCAL_AXIS_M, "Drive target stays inside the 1 km render-origin cell")
	_assert(Vector2(rig.global_position.x, rig.global_position.z).distance_to(Vector2(target_render.x, target_render.z)) < 0.01, "Drive camera rig uses render-local target coordinates")
	var reconstructed: Vector3 = rig.call("render_to_world_position", target_render)
	_assert(reconstructed.distance_to(target.global_position) < 0.01, "render-to-world conversion reconstructs logical target")
	_assert(camera.near >= 0.25 and camera.near <= 1.0, "Drive camera near plane stays in the local-driving precision range")
	_assert(camera.far <= 5000.01 and camera.far / camera.near <= 20000.0, "Drive camera far/near ratio remains bounded")

	var main := MainScript.new() as Node3D
	main.set("camera_rig", rig)
	main.set("current_layer_spacing", float(main.call("_layer_spacing")))
	var road_height := float(main.call("get_road_surface_height"))
	var urban_background_height := float(main.call("_background_height", 3))
	var effective_decorative_height := minf(urban_background_height, -0.20)
	_assert(road_height - effective_decorative_height >= MIN_DRIVE_DECORATIVE_CLEARANCE_M, "Drive physical surface has a measurable margin above the highest decorative background layer")

	var vehicle_scene := load("res://scenes/player_vehicle.tscn") as PackedScene
	_assert(vehicle_scene != null, "player vehicle scene loads")
	var vehicle := vehicle_scene.instantiate() as Node3D
	root.add_child(vehicle)
	vehicle.call("set_world_position", TEST_WORLD_POSITION)
	vehicle.call("set_heading_rad", 0.73)
	var logical_before := vehicle.global_transform
	vehicle.call("set_render_origin_world", render_origin)
	var visual_root := vehicle.get_node("VisualRoot") as Node3D
	var expected_visual := vehicle.global_position - render_origin
	_assert(vehicle.global_transform.is_equal_approx(logical_before), "vehicle logical transform is unchanged by render rebasing")
	_assert(visual_root.top_level, "vehicle visual is detached from the large logical parent transform")
	_assert(visual_root.global_position.distance_to(expected_visual) < 0.01, "vehicle visual uses render-local world position")
	_assert(visual_root.global_basis.is_equal_approx(vehicle.global_basis), "vehicle visual preserves logical heading in render-local frame")

	var world := Node3D.new()
	var road_leaf := MeshInstance3D.new()
	road_leaf.position = TEST_WORLD_POSITION
	road_leaf.mesh = BoxMesh.new()
	world.add_child(road_leaf)

	# Model the real BRM2 failure: mesh vertices themselves carry the ~826 km
	# coordinates while the node transform is neutral. This must be CPU-localized
	# before upload instead of relying on an inverse node transform in the GPU.
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

	# Model the Sweden-scale ocean PlaneMesh separately. Drive must replace it with
	# a bounded local patch instead of sending country-scale vertices to the GPU.
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
	var building_group := Node3D.new()
	var building_leaf := MeshInstance3D.new()
	building_leaf.position = TEST_WORLD_POSITION
	building_leaf.mesh = BoxMesh.new()
	building_group.add_child(building_leaf)
	buildings.add_child(building_group)

	var gps_layer := GpsRouteDriveRenderAdapterScript.new()
	gps_layer.player = vehicle
	gps_layer.set("_camera_rig", rig)
	gps_layer.set("_camera", camera)
	var route_renderer := Node3D.new()
	gps_layer.route_renderer = route_renderer
	gps_layer.call("set_render_origin_world", render_origin)
	_assert(route_renderer.position.distance_to(Vector3(-render_origin.x, 0.0, -render_origin.z)) < 0.01, "GPS route renderer uses inverse Drive render origin")

	var viewport_center := root.get_viewport().get_visible_rect().size * 0.5
	var ray_origin := camera.project_ray_origin(viewport_center)
	var ray_direction := camera.project_ray_normal(viewport_center)
	if ray_direction.y < -0.000001:
		var t := -ray_origin.y / ray_direction.y
		if t > 0.0:
			var expected_world_hit: Vector3 = rig.call("render_to_world_position", ray_origin + ray_direction * t)
			var adapter_world_hit: Vector3 = gps_layer.call("_screen_to_ground", viewport_center)
			_assert(adapter_world_hit.distance_to(expected_world_hit) < 0.01, "Drive GPS picking converts render hit back to logical world coordinates")

	var composition := DriveRenderOriginCompositionScript.new()
	composition.set("_camera_rig", rig)
	composition.set("_world", world)
	composition.set("_poi_layer", poi)
	composition.set("_cloud_field", cloud)
	composition.set("_building_layer", buildings)
	composition.set("_gps_route_layer", gps_layer)
	composition.call("_sync_render_origin")
	var expected_offset := Vector2(-render_origin.x, -render_origin.z)
	_assert(Vector2(world.position.x, world.position.z).length() < 0.01, "World root remains neutral in Drive")
	_assert(Vector2(buildings.position.x, buildings.position.z).length() < 0.01, "Building root remains neutral in Drive")
	_assert(Vector2(poi.position.x, poi.position.z).distance_to(expected_offset) < 0.01, "POI presentation root uses inverse Drive render origin")
	_assert(Vector2(cloud.position.x, cloud.position.z).distance_to(expected_offset) < 0.01, "cloud presentation root uses inverse Drive render origin")
	_assert(Vector2(road_leaf.position.x, road_leaf.position.z).distance_to(Vector2(target_render.x, target_render.z)) < 0.01, "road GPU-facing leaf is render-local")
	_assert(Vector2(building_leaf.position.x, building_leaf.position.z).distance_to(Vector2(target_render.x, target_render.z)) < 0.01, "building GPU-facing chunk is render-local")
	_assert(absf(road_leaf.position.x) <= MAX_LOCAL_AXIS_M and absf(road_leaf.position.z) <= MAX_LOCAL_AXIS_M, "road leaf stays inside the render-origin cell")
	_assert(absf(building_leaf.position.x) <= MAX_LOCAL_AXIS_M and absf(building_leaf.position.z) <= MAX_LOCAL_AXIS_M, "building leaf stays inside the render-origin cell")
	_assert(is_equal_approx(buildings.position.y, road_height), "presentation rebasing preserves #206 building surface height")

	_assert(background_leaf.mesh != background_mesh, "Drive replaces the canonical BRM2 mesh with a render-local mesh")
	_assert(Vector2(background_leaf.position.x, background_leaf.position.z).length() < 0.01, "localized BRM2 node itself remains near zero")
	_assert(background_leaf.position.y <= -0.20 + 0.0001, "Drive clamps decorative background below the physical surface")
	var background_bounds := _mesh_vertex_bounds(background_leaf.mesh as ArrayMesh)
	_assert(background_bounds["max_abs_x"] <= MAX_LOCAL_AXIS_M + 20.0 and background_bounds["max_abs_z"] <= MAX_LOCAL_AXIS_M + 20.0, "BRM2 GPU vertices are local at the prior failing coordinate")
	var local_center := Vector2(float(background_bounds["center_x"]), float(background_bounds["center_z"]))
	_assert(local_center.distance_to(Vector2(target_render.x, target_render.z)) < 1.0, "localized BRM2 triangle remains spatially aligned with the Drive target")

	_assert(ground_leaf.mesh is PlaneMesh and ground_leaf.mesh != sweden_plane, "Drive replaces the Sweden-scale ocean plane")
	var local_ground := ground_leaf.mesh as PlaneMesh
	_assert(local_ground.size.x <= MAX_DRIVE_GROUND_DIAMETER_M and local_ground.size.y <= MAX_DRIVE_GROUND_DIAMETER_M, "Drive ocean plane has bounded local dimensions")
	_assert(Vector2(ground_leaf.position.x, ground_leaf.position.z).length() < 0.01, "Drive ocean patch is centered in the render-local frame")

	var localized_background_before := background_leaf.mesh
	var localized_ground_before := ground_leaf.mesh
	for _frame in range(120):
		composition.call("_sync_render_origin")
	_assert(background_leaf.mesh == localized_background_before, "120 repeated Drive syncs do not rebuild or drift BRM2 geometry inside one render cell")
	_assert(ground_leaf.mesh != sweden_plane and (ground_leaf.mesh as PlaneMesh).size == (localized_ground_before as PlaneMesh).size, "120 repeated Drive syncs keep the bounded ocean patch stable")
	_assert(Vector2(road_leaf.position.x, road_leaf.position.z).distance_to(Vector2(target_render.x, target_render.z)) < 0.01, "120 repeated Drive syncs do not drift road presentation")
	_assert(Vector2(building_leaf.position.x, building_leaf.position.z).distance_to(Vector2(target_render.x, target_render.z)) < 0.01, "120 repeated Drive syncs do not drift building presentation")

	# Crossing a render-origin cell boundary must rebuild from canonical mesh data,
	# not from the already-localized mesh, so precision does not accumulate error.
	target.position.x += 1100.0
	rig.call("_apply_drive_camera")
	var next_origin: Vector3 = rig.call("get_render_origin_world")
	_assert(next_origin != render_origin, "test crosses a Drive render-origin cell boundary")
	composition.call("_sync_render_origin")
	_assert(background_leaf.mesh != localized_background_before, "BRM2 local mesh is rebuilt when the render cell changes")
	var next_background_bounds := _mesh_vertex_bounds(background_leaf.mesh as ArrayMesh)
	_assert(float(next_background_bounds["max_abs_x"]) < 2000.0, "cell-boundary BRM2 rebuild remains locally bounded")

	rig.call("set_drive_mode", false)
	composition.call("_sync_render_origin")
	_assert((rig.call("get_render_origin_world") as Vector3).is_zero_approx(), "Map mode restores zero render origin")
	_assert(Vector2(world.position.x, world.position.z).length() < 0.01, "World root stays canonical in Map")
	_assert(Vector2(buildings.position.x, buildings.position.z).length() < 0.01, "Building root stays canonical in Map")
	_assert(Vector2(road_leaf.position.x, road_leaf.position.z).distance_to(Vector2(TEST_WORLD_POSITION.x, TEST_WORLD_POSITION.z)) < 0.01, "Map restores authoritative road child coordinates")
	_assert(background_leaf.mesh == background_mesh, "Map restores the canonical BRM2 mesh")
	_assert(ground_leaf.mesh == sweden_plane, "Map restores the canonical Sweden ocean plane")
	_assert(Vector2(building_leaf.position.x, building_leaf.position.z).distance_to(Vector2(TEST_WORLD_POSITION.x, TEST_WORLD_POSITION.z)) < 0.01, "Map restores authoritative building chunk coordinates")
	_assert(Vector2(poi.position.x, poi.position.z).length() < 0.01, "Map POI presentation restores canonical frame")
	_assert(Vector2(cloud.position.x, cloud.position.z).length() < 0.01, "Map cloud presentation restores canonical frame")
	_assert(route_renderer.position.is_zero_approx(), "Map GPS route renderer restores canonical world frame")
	vehicle.call("set_render_origin_world", Vector3.ZERO)
	_assert(visual_root.global_position.distance_to(vehicle.global_position) < 0.01, "vehicle visual restores logical Map position")

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
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	var max_abs_x := 0.0
	var max_abs_z := 0.0
	for surface_index in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			min_x = minf(min_x, vertex.x)
			max_x = maxf(max_x, vertex.x)
			min_z = minf(min_z, vertex.z)
			max_z = maxf(max_z, vertex.z)
			max_abs_x = maxf(max_abs_x, absf(vertex.x))
			max_abs_z = maxf(max_abs_z, absf(vertex.z))
	return {
		"center_x": (min_x + max_x) * 0.5,
		"center_z": (min_z + max_z) * 0.5,
		"max_abs_x": max_abs_x,
		"max_abs_z": max_abs_z,
	}

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("drive-render-origin test failed: " + message)
	quit(1)
