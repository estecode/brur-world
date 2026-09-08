extends SceneTree

## Headless input -> expected-output tests for the search-to-routing adapter.
## Dependencies: gps_search_route_adapter.gd and gps_route_model.gd only.

const AdapterScript = preload("res://scripts/gps_search_route_adapter.gd")
const RouteModelScript = preload("res://scripts/gps_route_model.gd")

class FakeRouteLayer extends Node:
	var route_model = RouteModelScript.new()
	var request_count: int = 0
	var refresh_count: int = 0

	func set_destination(point: Vector2) -> bool:
		if not point.is_finite():
			return false
		route_model.set_destination(point)
		request_count += 1
		return true

	func add_waypoint(point: Vector2) -> bool:
		if not point.is_finite():
			return false
		route_model.add_waypoint(point)
		refresh_count += 1
		if route_model.has_destination():
			request_count += 1
		return true

func _init() -> void:
	var route_layer := FakeRouteLayer.new()

	_assert(AdapterScript._apply_destination(route_layer, Vector2(10.0, 20.0)), "destination adapter succeeds")
	_assert(route_layer.route_model.has_destination(), "destination becomes route-model state")
	_assert(route_layer.route_model.destination() == Vector2(10.0, 20.0), "destination coordinate is exact")
	_assert(route_layer.request_count == 1, "destination triggers one public route command")

	_assert(AdapterScript._apply_waypoint(route_layer, Vector2(30.0, 40.0)), "waypoint adapter succeeds")
	_assert(route_layer.route_model.waypoints() == [Vector2(30.0, 40.0)], "waypoint coordinate is exact")
	_assert(route_layer.refresh_count == 1, "waypoint presentation command occurs once")
	_assert(route_layer.request_count == 2, "waypoint reroutes when destination exists")

	var empty_route_layer := FakeRouteLayer.new()
	_assert(AdapterScript._apply_waypoint(empty_route_layer, Vector2(5.0, 6.0)), "waypoint without destination succeeds")
	_assert(empty_route_layer.request_count == 0, "waypoint without destination does not route")
	_assert(empty_route_layer.refresh_count == 1, "waypoint without destination still updates presentation")

	_assert(not AdapterScript._apply_destination(null, Vector2.ZERO), "null route layer is rejected")
	_assert(not AdapterScript._apply_waypoint(route_layer, Vector2(INF, INF)), "invalid coordinate is rejected")

	empty_route_layer.free()
	route_layer.free()

	print("godot gps search-route adapter tests: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("gps search-route adapter test failed: " + message)
	quit(1)
