extends SceneTree

## Verifies Drive presentation rebasing keeps logical world state authoritative while rendering in a small stable local cell.
##
## Dependencies:
## - camera_controller.gd owns the presentation-only Drive render-origin conversion.
## - drive_render_origin_composition.gd rebases GPU-facing presentation leaves instead of cancelling huge parent/child coordinates.
## - player_vehicle.tscn uses Vehicle's VisualRoot adapter without moving logical vehicle state.
## - gps_route_drive_render_adapter.gd rebases route presentation and converts Drive picking back to logical world coordinates.

const CameraControllerScript = preload("res://scripts/camera_controller.gd")
const DriveRenderOriginCompositionScript = preload("res://scripts/drive_render_origin_composition.gd")
const GpsRouteDriveRenderAdapterScript = preload("res://scripts/gps_route_drive_render_adapter.gd")
const TEST_WORLD_POSITION := Vector3(52277.0, 0.06, 825907.0)
const MAX_LOCAL_AXIS_M := 512.01

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
	world.add_child(road_leaf)
	var background_leaf := MeshInstance3D.new()
	background_leaf.position = Vector3(0.0, -0.25, 0.0)
	world.add_child(background_leaf)

	var poi := Node3D.new()
	var cloud := Node3D.new()
	var buildings := Node3D.new()
	buildings.position.y = 0.06
	var building_group := Node3D.new()
	var building_leaf := MeshInstance3D.new()
	building_leaf.position = TEST_WORLD_POSITION
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
	_assert(Vector2(world.position.x, world.position.z).length() < 0.01, "World root remains neutral in Drive instead of cancelling huge child coordinates")
	_assert(Vector2(buildings.position.x, buildings.position.z).length() < 0.01, "Building root remains neutral in Drive instead of cancelling huge chunk coordinates")
	_assert(Vector2(poi.position.x, poi.position.z).distance_to(expected_offset) < 0.01, "POI presentation root uses inverse Drive render origin")
	_assert(Vector2(cloud.position.x, cloud.position.z).distance_to(expected_offset) < 0.01, "cloud presentation root uses inverse Drive render origin")
	_assert(Vector2(road_leaf.position.x, road_leaf.position.z).distance_to(Vector2(target_render.x, target_render.z)) < 0.01, "road GPU-facing leaf is render-local rather than a huge child under an inverse huge parent")
	_assert(Vector2(background_leaf.position.x, background_leaf.position.z).distance_to(expected_offset) < 0.01, "background presentation leaf receives the Drive origin directly")
	_assert(Vector2(building_group.position.x, building_group.position.z).length() < 0.01, "building grouping node stays neutral")
	_assert(Vector2(building_leaf.position.x, building_leaf.position.z).distance_to(Vector2(target_render.x, target_render.z)) < 0.01, "building GPU-facing chunk is render-local rather than a huge child under an inverse huge parent")
	_assert(absf(road_leaf.position.x) <= MAX_LOCAL_AXIS_M and absf(road_leaf.position.z) <= MAX_LOCAL_AXIS_M, "road leaf stays inside the render-origin cell")
	_assert(absf(building_leaf.position.x) <= MAX_LOCAL_AXIS_M and absf(building_leaf.position.z) <= MAX_LOCAL_AXIS_M, "building leaf stays inside the render-origin cell")
	_assert(is_equal_approx(buildings.position.y, 0.06), "presentation rebasing preserves #206 building surface height")

	# Re-running the composition must be idempotent; otherwise a per-frame origin
	# sync would drift presentation nodes and recreate the visible instability.
	composition.call("_sync_render_origin")
	_assert(Vector2(road_leaf.position.x, road_leaf.position.z).distance_to(Vector2(target_render.x, target_render.z)) < 0.01, "repeated Drive sync does not double-subtract road origin")
	_assert(Vector2(building_leaf.position.x, building_leaf.position.z).distance_to(Vector2(target_render.x, target_render.z)) < 0.01, "repeated Drive sync does not double-subtract building origin")

	rig.call("set_drive_mode", false)
	composition.call("_sync_render_origin")
	_assert((rig.call("get_render_origin_world") as Vector3).is_zero_approx(), "Map mode restores zero render origin")
	_assert(Vector2(world.position.x, world.position.z).length() < 0.01, "World root stays canonical in Map")
	_assert(Vector2(buildings.position.x, buildings.position.z).length() < 0.01, "Building root stays canonical in Map")
	_assert(Vector2(road_leaf.position.x, road_leaf.position.z).distance_to(Vector2(TEST_WORLD_POSITION.x, TEST_WORLD_POSITION.z)) < 0.01, "Map restores authoritative road child coordinates")
	_assert(Vector2(background_leaf.position.x, background_leaf.position.z).length() < 0.01, "Map restores canonical background child coordinates")
	_assert(Vector2(building_leaf.position.x, building_leaf.position.z).distance_to(Vector2(TEST_WORLD_POSITION.x, TEST_WORLD_POSITION.z)) < 0.01, "Map restores authoritative building chunk coordinates")
	_assert(Vector2(poi.position.x, poi.position.z).length() < 0.01, "Map POI presentation restores canonical frame")
	_assert(Vector2(cloud.position.x, cloud.position.z).length() < 0.01, "Map cloud presentation restores canonical frame")
	_assert(route_renderer.position.is_zero_approx(), "Map GPS route renderer restores canonical world frame")
	vehicle.call("set_render_origin_world", Vector3.ZERO)
	_assert(visual_root.global_position.distance_to(vehicle.global_position) < 0.01, "vehicle visual restores logical Map position")

	composition.free()
	route_renderer.free()
	gps_layer.free()
	vehicle.free()
	target.free()
	rig.free()
	print("godot drive-render-origin tests: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("drive-render-origin test failed: " + message)
	quit(1)
