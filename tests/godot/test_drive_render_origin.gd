extends SceneTree

## Verifies Drive presentation rebasing keeps logical world state authoritative while rendering in a small stable local cell.
##
## Dependencies:
## - camera_controller.gd owns the presentation-only Drive render-origin conversion.
## - drive_render_origin_composition.gd rebases presentation roots only.
## - player_vehicle.tscn uses Vehicle's VisualRoot adapter without moving logical vehicle state.
## - gps_route_layer.gd supplies the production player accessor used by composition.

const CameraControllerScript = preload("res://scripts/camera_controller.gd")
const DriveRenderOriginCompositionScript = preload("res://scripts/drive_render_origin_composition.gd")
const GpsRouteLayerScript = preload("res://scripts/gps_route_layer.gd")
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
	var poi := Node3D.new()
	var cloud := Node3D.new()
	var buildings := Node3D.new()
	buildings.position.y = 0.06
	var gps_layer := GpsRouteLayerScript.new()
	gps_layer.player = vehicle
	var composition := DriveRenderOriginCompositionScript.new()
	composition.set("_camera_rig", rig)
	composition.set("_world", world)
	composition.set("_poi_layer", poi)
	composition.set("_cloud_field", cloud)
	composition.set("_building_layer", buildings)
	composition.set("_gps_route_layer", gps_layer)
	composition.call("_sync_render_origin")
	var expected_offset := Vector2(-render_origin.x, -render_origin.z)
	for presentation in [world, poi, cloud, buildings]:
		_assert(Vector2(presentation.position.x, presentation.position.z).distance_to(expected_offset) < 0.01, "presentation root uses inverse Drive render origin")
	_assert(is_equal_approx(buildings.position.y, 0.06), "presentation rebasing preserves #206 building surface height")

	rig.call("set_drive_mode", false)
	composition.call("_sync_render_origin")
	_assert((rig.call("get_render_origin_world") as Vector3).is_zero_approx(), "Map mode restores zero render origin")
	for presentation in [world, poi, cloud, buildings]:
		_assert(Vector2(presentation.position.x, presentation.position.z).length() < 0.01, "Map presentation restores canonical world frame")
	vehicle.call("set_render_origin_world", Vector3.ZERO)
	_assert(visual_root.global_position.distance_to(vehicle.global_position) < 0.01, "vehicle visual restores logical Map position")

	composition.free()
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
