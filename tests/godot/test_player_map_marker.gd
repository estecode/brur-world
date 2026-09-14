extends SceneTree

## Headless regression tests for player Map-mode presentation scaling and vehicle integrity.
##
## Dependencies:
## - player_map_marker.gd owns zoom scaling and reuses player_car_visual.gd for geometry.
## - scenes/main.tscn supplies the production CameraRig used for projected-size regression coverage.
## - player_vehicle.tscn/vehicle.gd own the unchanged production vehicle dimensions.
## - gps_route_layer.gd composes the marker without scaling the simulation vehicle.

const PlayerMapMarkerScript = preload("res://scripts/player_map_marker.gd")
const GpsRouteLayerScript = preload("res://scripts/gps_route_layer.gd")

const REFERENCE_ALTITUDES_M := [760000.0, 80000.0, 8000.0, 500.0, 50.0]

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
	_test_scale_is_monotonic_and_continuous()
	_test_marker_is_recognizable_car_shape()
	_test_vehicle_physics_dimensions_are_unchanged()
	_test_gps_composition_never_scales_simulation_vehicle()
	await _test_production_camera_reference_progression()
	print("godot player-map-marker tests: OK")
	quit(0)

func _test_scale_converges_to_physical_size_near_ground() -> void:
	_assert(_approx(PlayerMapMarkerScript.scale_for_distance(50.0), 1.0), "maximum/near-ground Map view uses physical 1:1 presentation scale")
	_assert(_approx(PlayerMapMarkerScript.scale_for_distance(500.0), 1.0), "close street-level Map view remains physical scale")
	_assert(PlayerMapMarkerScript.scale_for_distance(1200.0) > 1.0, "visibility boost begins smoothly only after the close physical-scale range")
	var size: Vector2 = PlayerMapMarkerScript.physical_size_m()
	_assert(_approx(size.x, 1.8) and _approx(size.y, 4.5), "map car base dimensions match a realistic passenger car")

func _test_scale_is_monotonic_and_continuous() -> void:
	var distances := [50.0, 500.0, 600.0, 900.0, 1200.0, 5000.0, 20000.0, 100000.0, 800000.0, 1400000.0]
	var previous := 0.0
	for distance in distances:
		var current := float(PlayerMapMarkerScript.scale_for_distance(distance))
		_assert(current >= previous - 0.0001, "visual boost grows monotonically only as camera moves farther away")
		_assert(current >= 1.0 and current <= 8192.0, "visual scale remains inside deterministic bounds")
		previous = current

	var previous_distance := 600.0
	var previous_scale := float(PlayerMapMarkerScript.scale_for_distance(previous_distance))
	for index in range(1, 121):
		var t := float(index) / 120.0
		var distance := exp(lerpf(log(600.0), log(1400000.0), t))
		var current_scale := float(PlayerMapMarkerScript.scale_for_distance(distance))
		_assert(current_scale >= previous_scale - 0.0001, "dense zoom samples never reverse scale direction")
		_assert(current_scale <= previous_scale * 1.12 + 0.01, "dense zoom samples have no abrupt scale pop")
		previous_distance = distance
		previous_scale = current_scale

func _test_marker_is_recognizable_car_shape() -> void:
	var marker := PlayerMapMarkerScript.new() as Node3D
	get_root().add_child(marker)
	_assert(marker.get_node_or_null("CarVisual/Body") is MeshInstance3D, "marker has a passenger-car body")
	_assert(marker.get_node_or_null("CarVisual/Cabin") is MeshInstance3D, "marker has a distinct cabin")
	_assert(marker.get_node_or_null("CarVisual/Windshield") is MeshInstance3D, "marker exposes a contrasting windshield for orientation")
	_assert(marker.get_node_or_null("CarVisual/RearWindow") is MeshInstance3D, "marker exposes a contrasting rear window")
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
	layer.set_process(false)
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

func _test_production_camera_reference_progression() -> void:
	var production_scene := load("res://scenes/main.tscn") as PackedScene
	_assert(production_scene != null, "production main scene loads for Map car projection regression")
	var scene := production_scene.instantiate()
	var rig := scene.get_node_or_null("CameraRig") as Node3D
	_assert(rig != null, "production main wires CameraRig")
	scene.remove_child(rig)
	scene.free()
	get_root().add_child(rig)
	await process_frame
	rig.set_process(false)

	var camera := rig.get_node_or_null("Camera3D") as Camera3D
	_assert(camera != null, "production CameraRig owns Camera3D")
	var marker := PlayerMapMarkerScript.new() as Node3D
	get_root().add_child(marker)
	marker.global_position = Vector3(0.0, 0.75, 0.0)

	var scales: Array[float] = []
	var projected_fractions: Array[float] = []
	for altitude in REFERENCE_ALTITUDES_M:
		rig.call("set_view_altitude", Vector3.ZERO, altitude)
		var distance := float(rig.call("get_distance"))
		marker.call("set_view_state", distance, false, 0.0)
		var fraction := _projected_marker_length_fraction(camera, marker)
		scales.append(marker.scale.x)
		projected_fractions.append(fraction)
		print("PLAYER_MAP_SCALE_DEBUG altitude_m=%.0f distance_m=%.1f scale=%.3f projected_height_fraction=%.5f" % [altitude, distance, marker.scale.x, fraction])

	_assert(scales[0] > scales[1] and scales[1] > scales[2] and scales[2] > scales[3], "production Map zoom progressively removes the far visibility boost")
	_assert(_approx(scales[3], 1.0), "block/street zoom has converged to physical scale")
	_assert(_approx(scales[4], 1.0), "maximum zoom remains exactly physical scale")
	_assert(scales[0] >= 4000.0, "Sweden/region overview uses a strong enough visibility boost to remain findable")
	_assert(scales[1] >= 250.0 and scales[1] <= 1500.0, "regional zoom uses a moderate visibility boost")
	_assert(scales[2] >= 15.0 and scales[2] <= 150.0, "city zoom uses a much smaller visibility boost")
	_assert(projected_fractions[0] >= 0.02 and projected_fractions[0] <= 0.16, "very wide production Map view keeps the car clearly visible without dominating the screen")
	_assert(projected_fractions[1] >= 0.015 and projected_fractions[1] <= 0.12, "regional production Map view keeps the car readable")
	_assert(projected_fractions[2] >= 0.008 and projected_fractions[2] <= 0.10, "city production Map view keeps the car readable while approaching world scale")
	_assert(projected_fractions[4] > projected_fractions[3], "at physical 1:1 scale, zooming from block view to maximum zoom naturally enlarges the real car on screen rather than scaling the marker")

	marker.free()
	rig.free()
	await process_frame

func _projected_marker_length_fraction(camera: Camera3D, marker: Node3D) -> float:
	var half_length := float(PlayerMapMarkerScript.physical_size_m().y) * 0.5
	var front_world := marker.global_transform * Vector3(0.0, 0.0, -half_length)
	var rear_world := marker.global_transform * Vector3(0.0, 0.0, half_length)
	var front_screen := camera.unproject_position(front_world)
	var rear_screen := camera.unproject_position(rear_world)
	var viewport_height := maxf(1.0, get_root().get_viewport().get_visible_rect().size.y)
	return front_screen.distance_to(rear_screen) / viewport_height

func _approx(a: float, b: float, epsilon: float = 0.001) -> bool:
	return absf(a - b) <= epsilon

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
