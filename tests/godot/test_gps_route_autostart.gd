extends SceneTree

## Verifies that installing any valid route through GPS composition immediately enters GPS driving mode.
## Dependencies: gps_route_layer.gd public control API; fakes only provide explicit route-follower/UI/coordinate boundaries.

const GpsRouteLayerScript = preload("res://scripts/gps_route_layer.gd")

class FakeCoordinates:
	extends RefCounted
	func absolute_to_world(point: Vector2) -> Vector3:
		return Vector3(point.x, 0.0, point.y)

class FakeMain:
	extends Node3D
	var coordinates := FakeCoordinates.new()
	func get_world_coordinates():
		return coordinates

class FakeFollower:
	extends Node
	var route_points := PackedVector3Array()
	var enabled := false
	func set_route(points: PackedVector3Array, _speed_limits_mps: PackedFloat32Array = PackedFloat32Array()) -> void:
		route_points = points
	func set_follow_enabled(value: bool) -> bool:
		if value and route_points.size() < 2:
			return false
		enabled = value
		return true
	func clear_route() -> void:
		route_points = PackedVector3Array()

class FakeRouteUi:
	extends CanvasLayer
	var follow_available := false
	var follow_enabled := false
	var status := ""
	func set_follow_available(value: bool) -> void:
		follow_available = value
	func set_follow_enabled(value: bool) -> void:
		follow_enabled = value
	func set_status(value: String) -> void:
		status = value

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var layer: Node3D = GpsRouteLayerScript.new()
	var main := FakeMain.new()
	var follower := FakeFollower.new()
	var ui := FakeRouteUi.new()
	layer.set("_main", main)
	layer.set("_route_follower", follower)
	layer.set("route_ui", ui)

	var first_response := {
		"points": [[0.0, 0.0], [0.0, -50.0], [0.0, -100.0]],
		"speed_limits_mps": [13.9, 13.9, 13.9],
	}
	layer.call("_install_follow_route", first_response)
	_assert(bool(layer.call("is_follow_enabled")), "installing a valid route enables GPS mode in composition")
	_assert(follower.enabled, "route follower receives GPS ownership enable")
	_assert(ui.follow_available and ui.follow_enabled, "GPS UI agrees that follow is available and enabled")

	_assert(bool(layer.call("set_follow_enabled", false)), "manual takeover can still disable GPS after route installation")
	_assert(not follower.enabled and not ui.follow_enabled, "manual takeover keeps composition, follower, and UI state aligned")

	var replacement_response := {
		"points": [[0.0, 0.0], [50.0, -50.0], [100.0, -100.0]],
		"speed_limits_mps": [11.1, 11.1, 11.1],
	}
	layer.call("_install_follow_route", replacement_response)
	_assert(bool(layer.call("is_follow_enabled")), "a replacement route re-enters GPS mode after manual takeover")
	_assert(follower.enabled and ui.follow_enabled, "replacement route restores follower and UI GPS state together")

	layer.call("set_follow_enabled", false)
	layer.call("_install_follow_route", {"points": [[0.0, 0.0]], "speed_limits_mps": [13.9]})
	_assert(not bool(layer.call("is_follow_enabled")), "an invalid one-point route does not claim GPS mode")
	_assert(not ui.follow_available and not ui.follow_enabled, "invalid route remains unavailable in GPS UI")

	layer.free()
	main.free()
	follower.free()
	ui.free()
	print("godot GPS route-autostart tests: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("GPS route-autostart test failed: " + message)
	quit(1)
