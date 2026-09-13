extends SceneTree

## Headless contract tests for POI/building visibility, armed teleport, map/drive camera ownership and map-control scene wiring.
## Dependencies: production Main, PoiLayer, BuildingStreamLayer/BuildingRuntimeComposition, GpsRouteLayer, GpsRouteRenderer, MapControlsUi, CameraRig, player controller and player vehicle adapters.

const MainScript = preload("res://scripts/main.gd")
const PoiLayerScript = preload("res://scripts/poi_layer.gd")
const BuildingStreamLayerScript = preload("res://scripts/building_stream_layer.gd")
const BuildingRuntimeCompositionScript = preload("res://scripts/building_runtime_composition.gd")
const GpsRouteLayerScript = preload("res://scripts/gps_route_layer.gd")
const GpsRouteRendererScript = preload("res://scripts/gps_route_renderer.gd")
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
	_test_drive_camera_follows_heading_without_mutating_vehicle()
	_test_drive_surface_height_contract()
	_test_production_building_surface_contract()
	_test_drive_zoom_contract()
	_test_mode_transition_contract()
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
	poi_layer.set("manifest", {"fixture": true})
	poi_layer.set("refresh_accum", 0.0)
	poi_layer.call("_process", 1.0)
	_assert(_approx(float(poi_layer.get("refresh_accum")), 0.0), "disabled POI presentation skips refresh/rebuild work")
	poi_layer.call("set_presentation_enabled", true)
	_assert(bool(poi_layer.call("is_presentation_enabled")), "POI presentation can be restored")
	poi_layer.free()

func _test_teleport_is_explicit_and_preserves_vehicle_identity() -> void:
	var player_scene := load("res://scenes/player_vehicle.tscn") as PackedScene
	var player: Node3D = player_scene.instantiate() as Node3D
	get_root().add_child(player)
	var route_layer: Node = GpsRouteLayerScript.new()
	get_root().add_child(route_layer)
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
	player.queue_free()
	route_layer.queue_free()

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
	_assert(labels.has("HUS"), "map controls expose building visibility")
	_assert(labels.has("Teleport"), "map controls expose armed teleport")
	_assert(labels.has("Follow car"), "map controls expose optional map follow")
	_assert(labels.has("Drive mode"), "map controls expose explicit Drive mode")
	_assert(not labels.has("Lund"), "map controls do not duplicate the existing Lund debug control")
	controls.free()

func _new_rig() -> Node3D:
	var rig := CameraControllerScript.new() as Node3D
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	get_root().add_child(rig)
	return rig

func _test_camera_mode_and_follow_contract() -> void:
	var rig := _new_rig()
	rig.set("mode_transition_seconds", 0.0)
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

func _test_drive_camera_follows_heading_without_mutating_vehicle() -> void:
	var rig := _new_rig()
	rig.set("mode_transition_seconds", 0.0)
	var camera := rig.get_node("Camera3D") as Camera3D
	var player_scene := load("res://scenes/player_vehicle.tscn") as PackedScene
	var player := player_scene.instantiate() as Node3D
	get_root().add_child(player)
	player.call("set_world_position", Vector3(25.0, 28.0, 40.0))
	player.call("set_motion_state", 11.0, PI * 0.5)
	var before_position := player.global_position
	var before_heading := float(player.call("heading_rad"))
	var before_speed := float(player.call("speed_mps"))
	var before_owner := int(player.call("control_owner"))
	rig.call("set_follow_target", player)
	rig.call("set_drive_mode", true)
	var forward := Vector3(-sin(before_heading), 0.0, -cos(before_heading)).normalized()
	var relative_camera := camera.global_position - player.global_position
	var camera_forward := -camera.global_transform.basis.z
	_assert(relative_camera.dot(forward) < 0.0, "Drive camera is positioned behind the vehicle heading")
	_assert(relative_camera.y >= float(rig.get("drive_height_m")) - 0.001, "Drive camera keeps configured clearance above the elevated route/player surface")
	_assert(camera_forward.dot(forward) > 0.5, "Drive camera looks primarily along the vehicle driving direction")
	_assert(camera_forward.y < -0.05, "Drive camera looks down toward the road instead of under the world")
	_assert(_approx(player.global_position.x, before_position.x) and _approx(player.global_position.y, before_position.y) and _approx(player.global_position.z, before_position.z), "switching to Drive does not move the vehicle")
	_assert(_approx(float(player.call("heading_rad")), before_heading), "switching to Drive does not change vehicle heading")
	_assert(_approx(float(player.call("speed_mps")), before_speed), "switching to Drive does not change vehicle speed")
	_assert(int(player.call("control_owner")) == before_owner, "switching to Drive does not change control ownership")
	player.free()
	rig.free()

func _test_drive_surface_height_contract() -> void:
	var rig := _new_rig()
	rig.set("mode_transition_seconds", 0.0)
	rig.call("set_drive_mode", true)

	var main := MainScript.new() as Node3D
	main.set("camera_rig", rig)
	main.set("current_layer_spacing", float(main.call("_layer_spacing")))
	var road_height := float(main.call("get_road_surface_height"))
	_assert(road_height > 0.0 and road_height <= 0.10, "Drive mode compresses artificial map layers to the physical road surface")

	var player_scene := load("res://scenes/player_vehicle.tscn") as PackedScene
	var player := player_scene.instantiate() as Node3D
	var route_layer := GpsRouteLayerScript.new() as Node3D
	var renderer := GpsRouteRendererScript.new() as Node3D
	route_layer.set("_main", main)
	route_layer.set("_camera_rig", rig)
	route_layer.set("route_renderer", renderer)
	route_layer.set("player", player)
	route_layer.call("_update_visual_height")

	_assert(_approx(player.position.y, road_height), "Player root sits on the road surface instead of the GPS presentation layer")
	var route_height := float(renderer.call("route_height"))
	_assert(route_height > road_height, "GPS route is rendered above the road surface")
	_assert(route_height - road_height <= 0.20, "GPS route remains visually attached to the road in Drive mode")

	player.free()
	renderer.free()
	route_layer.free()
	main.free()
	rig.free()

func _test_production_building_surface_contract() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	var main := main_scene.instantiate() as Node3D
	get_root().add_child(main)
	var building_layer := main.get_node_or_null("BuildingLayer") as Node3D
	var building_runtime := main.get_node_or_null("BuildingRuntimeComposition")
	_assert(building_layer != null, "production scene contains BuildingLayer")
	_assert(building_runtime != null, "production scene contains BuildingRuntimeComposition")
	_assert(_approx(float(building_layer.get("base_height_m")), 0.0), "production building base sits on the physical world surface")
	_assert(_approx(float(building_runtime.get("base_height_m")), 0.0), "building runtime composition uses the physical world surface")
	main.queue_free()

func _test_drive_zoom_contract() -> void:
	var rig := _new_rig()
	rig.set("mode_transition_seconds", 0.0)
	rig.call("set_drive_mode", true)
	var start_distance := float(rig.call("get_distance"))
	rig.call("_zoom", 1.0)
	var zoomed_out := float(rig.call("get_distance"))
	_assert(zoomed_out > start_distance, "Drive zoom-out increases camera distance")
	rig.call("_zoom", -1.0)
	var zoomed_back := float(rig.call("get_distance"))
	_assert(zoomed_back < zoomed_out, "Drive zoom-in decreases camera distance")
	rig.free()

func _test_mode_transition_contract() -> void:
	var rig := _new_rig()
	var target := Node3D.new()
	get_root().add_child(target)
	rig.call("set_follow_target", target)
	rig.call("set_drive_mode", true)
	_assert(bool(rig.call("is_mode_transition_active")), "Map to Drive begins a camera transition")
	rig.call("_process", float(rig.get("mode_transition_seconds")) + 0.1)
	_assert(not bool(rig.call("is_mode_transition_active")), "Map to Drive transition completes")
	rig.call("set_drive_mode", false)
	_assert(bool(rig.call("is_mode_transition_active")), "Drive to Map begins a camera transition")
	rig.call("_process", float(rig.get("mode_transition_seconds")) + 0.1)
	_assert(not bool(rig.call("is_mode_transition_active")), "Drive to Map transition completes")
	target.free()
	rig.free()

func _test_player_steering_direction_contract() -> void:
	var controller := PlayerVehicleControllerScript.new()
	var left := float(controller.call("steering_input_from_actions", 1.0, 0.0))
	var right := float(controller.call("steering_input_from_actions", 0.0, 1.0))
	_assert(left > 0.0, "left steering action produces positive steering input")
	_assert(right < 0.0, "right steering action produces negative steering input")
	controller.free()

func _test_main_scene_control_wiring() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	var root := scene.instantiate()
	_assert(root.get_node_or_null("MapControlsUi") != null, "production scene wires MapControlsUi")
	_assert(root.get_node_or_null("PoiLayer") != null, "production scene wires PoiLayer")
	_assert(root.get_node_or_null("BuildingLayer") != null, "production scene wires BuildingLayer")
	_assert(root.get_node_or_null("GpsRouteLayer") != null, "production scene wires GpsRouteLayer")
	root.free()

func _approx(a: float, b: float, tolerance: float = 0.001) -> bool:
	return absf(a - b) <= tolerance

func _assert(condition: bool, message: String) -> void:
	if not condition:
		push_error("map controls test failed: " + message)
		quit(1)
