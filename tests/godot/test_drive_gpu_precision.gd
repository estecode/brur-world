extends SceneTree

## Measures GPU-facing Drive precision plus static-presentation resource churn across render-origin cells.
##
## Dependencies:
## - camera_controller.gd owns the Drive render-origin cell and camera near/far range.
## - drive_render_origin_composition.gd localizes production presentation without changing logical world coordinates.
## - gps_route_drive_render_adapter.gd supplies the same explicit composition boundary used by the game.

const CameraControllerScript = preload("res://scripts/camera_controller.gd")
const DriveRenderOriginCompositionScript = preload("res://scripts/drive_render_origin_composition.gd")
const GpsRouteDriveRenderAdapterScript = preload("res://scripts/gps_route_drive_render_adapter.gd")

const TEST_WORLD_POSITION := Vector3(52277.0, 0.06, 825907.0)
const ROAD_TILE_ORIGIN := Vector3(32000.0, 0.06, 800000.0)
const MAX_FLOAT32_EFFECTIVE_ERROR_M := 0.02
const MAX_RENDER_CELL_AXIS_M := 512.0
const FRUSTUM_EDGE_MARGIN_M := 64.0

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
	var target_render: Vector3 = rig.call("world_to_render_position", TEST_WORLD_POSITION)
	var road_local_vertex := TEST_WORLD_POSITION - ROAD_TILE_ORIGIN
	_assert(absf(road_local_vertex.x) < 32000.0 and absf(road_local_vertex.z) < 32000.0, "road fixture uses production-scale tile-local coordinates")
	var rebased_tile_origin := ROAD_TILE_ORIGIN - render_origin
	var gpu_x := _f32(_f32(rebased_tile_origin.x) + _f32(road_local_vertex.x))
	var gpu_z := _f32(_f32(rebased_tile_origin.z) + _f32(road_local_vertex.z))
	var gpu_error := Vector2(gpu_x, gpu_z).distance_to(Vector2(target_render.x, target_render.z))
	_assert(gpu_error <= MAX_FLOAT32_EFFECTIVE_ERROR_M, "32 km BRT1 tile arithmetic stays below the explicit 2 cm Drive precision budget")

	var world := Node3D.new()
	var road_leaf := MeshInstance3D.new()
	road_leaf.position = ROAD_TILE_ORIGIN
	var road_mesh := ArrayMesh.new()
	road_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _triangle_arrays(PackedVector3Array([
		road_local_vertex + Vector3(-2.0, 0.0, -2.0),
		road_local_vertex + Vector3(2.0, 0.0, -2.0),
		road_local_vertex + Vector3(0.0, 0.0, 2.0),
	])))
	road_leaf.mesh = road_mesh
	world.add_child(road_leaf)

	var background_leaf := MeshInstance3D.new()
	var background_mesh := ArrayMesh.new()
	background_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _triangle_arrays(PackedVector3Array([
		TEST_WORLD_POSITION + Vector3(-10.0, 0.0, -10.0),
		TEST_WORLD_POSITION + Vector3(10.0, 0.0, -10.0),
		TEST_WORLD_POSITION + Vector3(0.0, 0.0, 10.0),
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

	var buildings := Node3D.new()
	var poi := Node3D.new()
	var cloud := Node3D.new()
	var gps_layer := GpsRouteDriveRenderAdapterScript.new()
	gps_layer.player = target
	gps_layer.set("_camera_rig", rig)
	gps_layer.set("_camera", camera)
	gps_layer.route_renderer = Node3D.new()

	var composition := DriveRenderOriginCompositionScript.new()
	composition.set("_camera_rig", rig)
	composition.set("_world", world)
	composition.set("_poi_layer", poi)
	composition.set("_cloud_field", cloud)
	composition.set("_building_layer", buildings)
	composition.set("_gps_route_layer", gps_layer)
	composition.call("_sync_render_origin")

	var rendered_vertex := road_leaf.position + road_local_vertex
	_assert(Vector2(rendered_vertex.x, rendered_vertex.z).distance_to(Vector2(target_render.x, target_render.z)) < 0.01, "production-scale road tile resolves to correct render-local position")

	_assert(ground_leaf.mesh is PlaneMesh and ground_leaf.mesh != sweden_plane, "Drive replaces Sweden-scale ocean plane with local patch")
	var local_ground := ground_leaf.mesh as PlaneMesh
	var required_radius := camera.far + MAX_RENDER_CELL_AXIS_M + float(rig.get("drive_max_distance_m")) + FRUSTUM_EDGE_MARGIN_M
	_assert(local_ground.size.x * 0.5 >= required_radius and local_ground.size.y * 0.5 >= required_radius, "local ocean patch covers full Drive far range at render-cell edge")

	var stable_ground_mesh := ground_leaf.mesh
	var stable_background_mesh := background_leaf.mesh
	for _frame in range(120):
		composition.call("_sync_render_origin", false)
	_assert(ground_leaf.mesh == stable_ground_mesh, "local ocean mesh resource is stable for 120 same-cell syncs")
	_assert(background_leaf.mesh == stable_background_mesh, "localized BRM2 resource is stable for 120 same-cell syncs")

	# A 1 km cell crossing previously rebuilt the entire BRM2 ArrayMesh. The
	# resource identity must now remain stable so cell crossings cannot trigger a
	# Sweden-scale CPU mesh copy on the frame thread.
	target.position.x += 1100.0
	rig.call("_apply_drive_camera")
	var next_origin: Vector3 = rig.call("get_render_origin_world")
	_assert(next_origin != render_origin, "precision fixture crosses a render-origin cell")
	composition.call("_sync_render_origin", false)
	_assert(background_leaf.mesh == stable_background_mesh, "cell crossing keeps exact BRM2 mesh resource")

	composition.free()
	gps_layer.route_renderer.free()
	gps_layer.free()
	world.free()
	buildings.free()
	poi.free()
	cloud.free()
	target.free()
	rig.free()
	print("godot drive-gpu-precision tests: OK")
	quit(0)

func _f32(value: float) -> float:
	var packed := PackedFloat32Array([value])
	return float(packed[0])

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

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("drive-gpu-precision test failed: " + message)
	quit(1)
