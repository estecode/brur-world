extends SceneTree

## Verifies Drive presentation rebasing keeps logical world state authoritative while rendering near zero.
##
## Dependencies:
## - camera_controller.gd owns the presentation-only Drive render-origin conversion.
## - drive_render_origin_composition.gd rebases presentation roots only.
## - player_vehicle.tscn uses Vehicle's VisualRoot adapter without moving logical vehicle state.
## - gps_route_layer.gd supplies the production player accessor used by composition.

const CameraControllerScript = preload("res://scripts/camera_controller.gd")
const DriveRenderOriginCompositionScript = preload("res://scripts/drive_render_origin_composition.gd")
const GpsRouteLayerScript = preload("res://scripts/gps_route_layer.gd")

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
	target.position = Vector3(52277.0, 0.06, 825907.0)
	root.add_child(target)
	rig.call("set_follow_target", target)
	rig.call("set_drive_mode", true)
	await process_frame

	var render_origin: Vector3 = rig.call("get_render_origin_world")
	_assert(render_origin.distance_to(Vector3(52277.0, 0.0, 825907.0)) < 0.01, "Drive render origin follows logical target x/z")
	_assert(Vector2(rig.global_position.x, rig.global_position.z).length() < 0.01, "Drive camera rig renders near local origin")
	var reconstructed: Vector3 = rig.call("render_to_world_position", Vector3.ZERO)
	_assert(reconstructed.distance_to(render_origin) < 0.01, "render-to-world conversion preserves logical origin")

	var vehicle_scene := load("res://scenes/player_vehicle.tscn") as PackedScene
	_assert(vehicle_scene != null, "player vehicle scene loads")
	var vehicle := vehicle_scene.instantiate() as Node3D
	root.add_child(vehicle)
	vehicle.call("set_world_position", Vector3(52277.0, 0.06, 825907.0))
	var logical_before := vehicle.global_position
	vehicle.call("set_render_origin_world", render_origin)
	var visual_root := vehicle.get_node("VisualRoot") as Node3D
	_assert(vehicle.global_position.distance_to(logical_before) < 0.001, "vehicle logical root is unchanged by render rebasing")
	_assert(Vector2(visual_root.global_position.x, visual_root.global_position.z).length() < 0.01, "vehicle visual renders near local origin")

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
	_assert(Vector2(visual_root.global_position.x, visual_root.global_position.z).distance_to(Vector2(vehicle.global_position.x, vehicle.global_position.z)) < 0.01, "vehicle visual restores logical Map position")

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
