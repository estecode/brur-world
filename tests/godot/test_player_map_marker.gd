extends SceneTree

## Headless regression tests for player Map-mode presentation scaling and vehicle integrity.
##
## Dependencies:
## - player_map_marker.gd owns visual car geometry and zoom scaling.
## - player_vehicle.tscn/vehicle.gd own the unchanged production vehicle dimensions.
## - gps_route_layer.gd composes the marker without scaling the simulation vehicle.

const PlayerMapMarkerScript = preload("res://scripts/player_map_marker.gd")
const GpsRouteLayerScript = preload("res://scripts/gps_route_layer.gd")

class FakeCameraRig extends Node3D:
	var distance_m := 200.0
	var driving := false
	func get_distance() -> float: return distance_m
	func is_driving_view() -> bool: return driving

class FakeRouteRenderer extends Node3D:
	var height_m := 0.4
	func update_height(_distance_m: float, road_height_m: float) -> void: height_m = road_height_m + 0.4
	func route_height() -> float: return height_m

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_scale_converges_to_physical_size_near_ground()
	_test_scale_is_monotonic_and_bounded()
	_test_marker_is_recognizable_car_shape()
	_test_vehicle_physics_dimensions_are_unchanged()
	_test_gps_composition_never_scales_simulation_vehicle()
	print("godot player-map-marker tests: OK")
	quit(0)

func _test_scale_converges_to_physical_size_near_ground() -> void:
	_assert(_approx(PlayerMapMarkerScript.scale_for_distance(50.0), 1.0), "near-ground map view uses physical 1:1 presentation scale")
	_assert(_approx(PlayerMapMarkerScript.scale_for_distance(250.0), 1.0), "near threshold remains physical scale")
	var size: Vector2 = PlayerMapMarkerScript.physical_size_m()
	_assert(_approx(size.x, 1.8) and _approx(size.y, 4.5), "map car base dimensions match a realistic passenger car")

func _test_scale_is_monotonic_and_bounded() -> void:
	var distances := [50.0, 250.0, 1000.0, 8000.0, 80000.0, 760000.0]
	var previous := 0.0
	for distance in distances:
		var current := float(PlayerMapMarkerScript.scale_for_distance(distance))
		_assert(current >= previous - 0.0001, "visual boost grows monotonically only as camera moves farther away")
		_assert(current >= 1.0 and current <= 28.0, "visual scale remains inside deterministic bounds")
		previous = current
	_assert(PlayerMapMarkerScript.scale_for_distance(1000.0) < PlayerMapMarkerScript.scale_for_distance(8000.0), "medium zoom is smaller than far zoom")
	_assert(PlayerMapMarkerScript.scale_for_distance(8000.0) < PlayerMapMarkerScript.scale_for_distance(80000.0), "far zoom remains more visible than city zoom")

func _test_marker_is_recognizable_car_shape() -> void:
	var marker := PlayerMapMarkerScript.new() as Node3D
	get_root().add_child(marker)
	_assert(marker.get_node_or_null("Body") is MeshInstance3D, "marker has a passenger-car body")
	_assert(marker.get_node_or_null("Cabin") is MeshInstance3D, "marker has a distinct cabin")
	_assert(marker.get_node_or_null("Windshield") is MeshInstance3D, "marker exposes a contrasting windshield for orientation")
	_assert(marker.get_node_or_null("RearWindow") is MeshInstance3D, "marker exposes a contrasting rear window")
	marker.call("set_view_state", 200.0, false, 0.75)
	_assert(_approx(marker.scale.x, 1.0) and _approx(marker.scale.z, 1.0), "near marker remains at physical scale")
	_assert(_approx(marker.rotation.y, 0.75), "marker follows vehicle heading")
	marker.call("set_view_state", 200.0, true, 0.75)
	_assert(not marker.visible, "map presentation hides in Drive mode")
	marker.free()

func _test_vehicle_physics_dimensions_are_unchanged() -> void:
	var scene := load("res://scenes/player_vehicle.tscn") as PackedScene
	var player := scene.instantiate() as Node3D
	get_root().add_child(player)
	_assert(_approx(float(player.get("length_m")), 4.5), "player simulation length remains 4.5 m")
	_assert(_approx(float(player.get("width_m")), 1.8), "player simulation width remains 1.8 m")
	_assert(player.scale.is_equal_approx(Vector3.ONE), "player simulation root starts unscaled")
	player.free()

func _test_gps_composition_never_scales_simulation_vehicle() -> void:
	var scene := load("res://scenes/player_vehicle.tscn") as PackedScene
	var player := scene.instantiate() as Node3D
	var rig := FakeCameraRig.new()
	var renderer := FakeRouteRenderer.new()
	var layer := GpsRouteLayerScript.new() as Node3D
	get_root().add_child(player)
	get_root().add_child(rig)
	get_root().add_child(renderer)
	get_root().add_child(layer)
	layer.set("player", player)
	layer.set("_camera_rig", rig)
	layer.set("route_renderer", renderer)
	layer.call("_create_player_marker")
	for distance in [100.0, 1000.0, 8000.0, 80000.0]:
		rig.distance_m = distance
		layer.call("_update_visual_height")
		_assert(player.scale.is_equal_approx(Vector3.ONE), "map zoom never changes simulation vehicle scale")
	var marker := layer.get_node_or_null("PlayerMapMarker") as Node3D
	_assert(marker != null, "GPS composition creates the production map-car presentation")
	rig.distance_m = 100.0
	layer.call("_update_visual_height")
	_assert(marker != null and _approx(marker.scale.x, 1.0), "GPS near map view converges presentation to physical scale")
	layer.free()
	renderer.free()
	rig.free()
	player.free()

func _approx(a: float, b: float, epsilon: float = 0.001) -> bool:
	return absf(a - b) <= epsilon

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
