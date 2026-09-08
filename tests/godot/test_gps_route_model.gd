extends SceneTree

## Headless input -> expected-output tests for the isolated Godot GPS route model.
## Dependencies: scripts/gps_route_model.gd only; no world data, rendering or native server.

func _init() -> void:
	var model := GpsRouteModel.new()
	_assert(model.waypoint_count() == 0, "starts with zero waypoints")
	_assert(not model.has_destination(), "starts without destination")

	model.add_waypoint(Vector2(20.0, 20.0))
	model.add_waypoint(Vector2(30.0, 30.0))
	model.add_waypoint(Vector2(25.0, 25.0), 1)
	_assert(model.waypoints() == [Vector2(20.0, 20.0), Vector2(25.0, 25.0), Vector2(30.0, 30.0)], "insert preserves explicit order")

	_assert(model.remove_waypoint(1), "remove middle succeeds")
	_assert(model.waypoints() == [Vector2(20.0, 20.0), Vector2(30.0, 30.0)], "remove middle returns expected order")
	_assert(not model.remove_waypoint(99), "invalid remove is clean")

	model.set_destination(Vector2(40.0, 40.0))
	var stops := model.ordered_stops(Vector2(10.0, 10.0))
	_assert(stops == [Vector2(10.0, 10.0), Vector2(20.0, 20.0), Vector2(30.0, 30.0), Vector2(40.0, 40.0)], "ordered stops are start -> waypoints -> destination")

	model.clear_waypoints()
	_assert(model.ordered_stops(Vector2(10.0, 10.0)) == [Vector2(10.0, 10.0), Vector2(40.0, 40.0)], "clearing waypoints leaves direct route")
	model.clear_destination()
	_assert(model.ordered_stops(Vector2(10.0, 10.0)) == [Vector2(10.0, 10.0)], "clearing destination leaves only start")

	print("godot gps route-model tests: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("gps route-model test failed: " + message)
	quit(1)
