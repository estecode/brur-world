extends SceneTree

## Headless input -> expected-output tests for the search-to-routing adapter.
## Dependencies: gps_search_route_adapter.gd and gps_route_model.gd only.

const AdapterScript = preload("res://scripts/gps_search_route_adapter.gd")
const RouteModelScript = preload("res://scripts/gps_route_model.gd")

class FakeRouteLayer extends Node:
	var route_model = RouteModelScript.new()
	var request_count: int = 0
	var refresh_count: int = 0

	func _request_current_plan() -> void:
		request_count += 1

	func _refresh_waypoint_ui() -> void:
		refresh_count += 1

func _init() -> void:
	var route_layer := FakeRouteLayer.new()

	_assert(AdapterScript._apply_destination(route_layer, Vector2(10.0, 20.0)), "destination adapter succeeds")
	_assert(route_layer.route_model.has_destination(), "destination becomes route-model state")
	_assert(route_layer.route_model.destination() == Vector2(10.0, 20.0), "destination coordinate is exact")
	_assert(route_layer.request_count == 1, "destination triggers one route request")

	_assert(AdapterScript._apply_waypoint(route_layer, Vector2(30.0, 40.0)), "waypoint adapter succeeds")
	_assert(route_layer.route_model.waypoints() == [Vector2(30.0, 40.0)], "waypoint coordinate is exact")
	_assert(route_layer.refresh_count == 1, "waypoint refreshes waypoint presentation once")
	_assert(route_layer.request_count == 2, "waypoint reroutes when destination exists")

	var empty_route_layer := FakeRouteLayer.new()
	_assert(AdapterScript._apply_waypoint(empty_route_layer, Vector2(5.0, 6.0)), "waypoint without destination succeeds")
	_assert(empty_route_layer.request_count == 0, "waypoint without destination does not route")
	_assert(empty_route_layer.refresh_count == 1, "waypoint without destination still refreshes presentation")

	_assert(not AdapterScript._apply_destination(null, Vector2.ZERO), "null route layer is rejected")
	_assert(not AdapterScript._apply_waypoint(route_layer, Vector2(INF, INF)), "invalid coordinate is rejected")

	print("godot gps search-route adapter tests: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("gps search-route adapter test failed: " + message)
	quit(1)
