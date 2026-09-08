extends SceneTree

## Headless contract tests for POI visibility, armed teleport and map-control scene wiring.
## Dependencies: production PoiLayer, GpsRouteLayer, player vehicle and main-scene adapters.

const PoiLayerScript = preload("res://scripts/poi_layer.gd")
const GpsRouteLayerScript = preload("res://scripts/gps_route_layer.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_poi_visibility_preserves_data()
	_test_teleport_is_explicit_and_preserves_vehicle_identity()
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

func _test_main_scene_control_wiring() -> void:
	var main_scene := load("res://scenes/main.tscn") as PackedScene
	_assert(main_scene != null, "main scene loads with map controls")
	var main: Node = main_scene.instantiate()
	var controls: Node = main.get_node_or_null("MapControlsUi")
	_assert(controls != null, "main scene includes map controls")
	_assert(controls.get("poi_layer_path") == NodePath("../PoiLayer"), "POI control uses explicit scene-composed dependency")
	_assert(controls.get("gps_route_layer_path") == NodePath("../GpsRouteLayer"), "teleport/follow control uses explicit GPS adapter dependency")
	_assert(controls.get("camera_rig_path") == NodePath("../CameraRig"), "camera control uses explicit CameraRig dependency")
	main.free()

func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.00001

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("map-controls test failed: " + message)
	quit(1)
