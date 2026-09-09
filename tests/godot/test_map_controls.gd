extends SceneTree

## Headless contract tests for POI visibility, armed teleport, map/drive camera ownership and map-control scene wiring.
## Dependencies: production PoiLayer, GpsRouteLayer, MapControlsUi, CameraRig, player controller and player vehicle adapters.

const PoiLayerScript = preload("res://scripts/poi_layer.gd")
const GpsRouteLayerScript = preload("res://scripts/gps_route_layer.gd")
const MapControlsUiScript = preload("res://scripts/map_controls_ui.gd")
const CameraControllerScript = preload("res://scripts/camera_controller.gd")
const PlayerVehicleControllerScript = preload("res://scripts/player_vehicle_controller.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_poi_visibility_preserves_data()
	_test_teleport_is_explicit_and_preserves_vehicle_identity()
	_test_map_controls_ui_builds_headlessly()
	_test_camera_mode_and_follow_contract()
	_test_player_steering_direction_contract()
	_test_main_scene_control_wiring()
	print("godot map-controls tests: OK")
	quit(0)

func _test_poi_visibility_preserves_data() -> void:
	var poi_layer: Node = PoiLayerScript.new()
	poi_layer.set("active_pois", [{"osm_id": 1}, {"osm_id": 2}])
	var before: Array = (poi_layer.get("active_pois") as Array).duplicate(true)
	poi_layer.call("set_presentation_enabled", false)
	_assert(not bool(poi_layer.call("is_presentation_enabled")), "POI presentation can be disabled")
	_assert((poi_layer.get("active_pois") as Array) == before, "POI presentation toggle does not delete runtime POI data")
	poi_layer.call("set_presentation_enabled", true)
	_assert(bool(poi_layer.call("is_presentation_enabled")), "POI presentation can be restored")
	poi_layer.free()

func _test_teleport_is_explicit_and_preserves_vehicle_identity() -> void:
	var player_scene := load("res://scenes/player_vehicle.tscn") as PackedScene
	var player: Node3D = player_scene.instantiate() as Node3D
	var route_layer: Node = GpsRouteLayerScript.new()
	route_layer.set("player", player)
	player.call("set_world_position", Vector3(10.0, 2.0, 20.0))
	player.call("set_motion_state", 12.0)
	var identity: int = player.get_instance_id()
	_assert(not bool(route_layer.call("is_teleport_armed")), "teleport starts unarmed")
	route_layer.call("set_teleport_armed", true)
	_assert(bool(route_layer.call("is_teleport_armed")), "teleport can be explicitly armed")
	_assert(bool(route_layer.call("teleport_player_to_world", Vector3(55.0, 0.0, -44.0))), "armed teleport target uses production vehicle API")
	route_layer.call("set_teleport_armed", false)
	_assert(player.get_instance_id() == identity, "teleport preserves the same player vehicle instance")
	_assert(_approx(player.global_position.x, 55.0) and _approx(player.global_position.z, -44.0), "teleport moves to the requested world coordinate")
	_assert(_approx(float(player.call("speed_mps")), 0.0), "teleport resets vehicle speed")
	player.free()
	route_layer.free()

func _test_map_controls_ui_builds_headlessly() -> void:
	var controls: CanvasLayer = MapControlsUiScript.new()
	get_root().add_child(controls)
	_assert(controls.get_child_count() == 1, "map controls build their panel during _ready")
	var panel := controls.get_child(0) as PanelContainer
	_assert(panel != null, "map controls panel exists after entering the tree")
	_assert(panel.get_child_count() == 1, "map controls panel contains its control row")
	var row := panel.get_child(0) as HBoxContainer
	var labels: Array[String] = []
	for child in row.get_children():
		if child is Button:
			labels.append((child as Button).text)
	_assert(labels.has("Show POIs"), "map controls expose POI visibility")
	_assert(labels.has("Teleport"), "map controls expose armed teleport")
	_assert(labels.has("Follow car"), "map controls expose optional map follow")
	_assert(labels.has("Drive mode"), "map controls expose explicit Drive mode")
	_assert(not labels.has("Lund"), "map controls do not duplicate the existing Lund debug control")
	controls.free()

func _test_camera_mode_and_follow_contract() -> void:
	var rig := CameraControllerScript.new() as Node3D
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	get_root().add_child(rig)
	var target := Node3D.new()
	target.position = Vector3(120.0, 0.0, -80.0)
	get_root().add_child(target)
	rig.call("set_follow_target", target)
	_assert(not bool(rig.call("is_driving_view")), "camera starts in explicit Map mode")
	rig.call("set_map_follow_enabled", true)
	_assert(bool(rig.call("is_map_follow_enabled")), "Follow car can be enabled in Map mode")
	var followed_focus: Vector3 = rig.call("get_focus_world") as Vector3
	_assert(_approx(followed_focus.x, 120.0) and _approx(followed_focus.z, -80.0), "Follow car centers on the player target")
	rig.call("_pan_pixels", Vector2(20.0, 0.0))
	_assert(not bool(rig.call("is_map_follow_enabled")), "manual map pan disengages Follow car")
	rig.call("set_drive_mode", true)
	_assert(bool(rig.call("is_driving_view")), "Drive mode is explicit and not inferred from camera altitude")
	rig.call("set_drive_mode", false)
	_assert(not bool(rig.call("is_driving_view")), "camera returns explicitly to Map mode")
	target.free()
	rig.free()

func _test_player_steering_direction_contract() -> void:
	_assert(float(PlayerVehicleControllerScript.steering_input(true, false)) > 0.0, "A maps to left steering")
	_assert(float(PlayerVehicleControllerScript.steering_input(false, true)) < 0.0, "D maps to right steering")
	_assert(_approx(float(PlayerVehicleControllerScript.steering_input(true, true)), 0.0), "opposing steering inputs cancel")

func _test_main_scene_control_wiring() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	_assert(main_scene != null, "main scene loads with map controls")
	var main: Node = main_scene.instantiate()
	var controls: Node = main.get_node_or_null("MapControlsUi")
	_assert(controls != null, "main scene includes map controls")
	_assert(controls.get("poi_layer_path") == NodePath("../PoiLayer"), "POI control uses explicit scene-composed dependency")
	_assert(controls.get("gps_route_layer_path") == NodePath("../GpsRouteLayer"), "teleport/follow control uses explicit GPS adapter dependency")
	_assert(controls.get("camera_rig_path") == NodePath("../CameraRig"), "camera control uses explicit CameraRig dependency")
	var camera_rig: Node = main.get_node_or_null("CameraRig")
	_assert(camera_rig != null and camera_rig.has_method("set_drive_mode"), "CameraRig exposes explicit Map/Drive mode API")
	_assert(camera_rig != null and camera_rig.has_method("set_map_follow_enabled"), "CameraRig exposes separate Map follow API")
	main.free()

func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.00001

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("map-controls test failed: " + message)
	quit(1)
