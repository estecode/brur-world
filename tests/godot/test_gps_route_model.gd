extends SceneTree

## Headless input -> expected-output tests for isolated Godot GPS route state/protocol.
## Dependencies: scripts/gps_route_model.gd and scripts/gps_protocol.gd only.

const GpsRouteModelScript = preload("res://scripts/gps_route_model.gd")
const GpsProtocolScript = preload("res://scripts/gps_protocol.gd")

func _init() -> void:
	var model = GpsRouteModelScript.new()
	_assert(model.waypoint_count() == 0, "starts with zero waypoints")
	_assert(not model.has_destination(), "starts without destination")
	_assert(model.preference() == "fastest", "starts with fastest preference")
	_assert(model.set_preference("avoid_small_roads"), "known preference is accepted")
	_assert(model.preference() == "avoid_small_roads", "preference state changes exactly")
	_assert(not model.set_preference("teleport"), "unknown preference is rejected")
	_assert(model.preference() == "avoid_small_roads", "invalid preference does not mutate state")

	model.add_waypoint(Vector2(20.0, 20.0))
	model.add_waypoint(Vector2(30.0, 30.0))
	model.add_waypoint(Vector2(25.0, 25.0), 1)
	_assert(model.waypoints() == [Vector2(20.0, 20.0), Vector2(25.0, 25.0), Vector2(30.0, 30.0)], "insert preserves explicit order")

	_assert(model.remove_waypoint(1), "remove middle succeeds")
	_assert(model.waypoints() == [Vector2(20.0, 20.0), Vector2(30.0, 30.0)], "remove middle returns expected order")
	_assert(not model.remove_waypoint(99), "invalid remove is clean")

	model.set_destination(Vector2(40.0, 40.0))
	var stops: Array[Vector2] = model.ordered_stops(Vector2(10.0, 10.0))
	_assert(stops == [Vector2(10.0, 10.0), Vector2(20.0, 20.0), Vector2(30.0, 30.0), Vector2(40.0, 40.0)], "ordered stops are start -> waypoints -> destination")
	var expected_wire := "plan avoid_small_roads 4 10.000000000 10.000000000 20.000000000 20.000000000 30.000000000 30.000000000 40.000000000 40.000000000\n"
	_assert(GpsProtocolScript.encode_plan(stops, model.preference()) == expected_wire, "protocol is exact and deterministic")
	_assert(GpsProtocolScript.encode_plan(stops, model.preference()) == expected_wire, "repeated protocol input is deterministic")
	var missing_destination: Array[Vector2] = [Vector2(1.0, 2.0)]
	_assert(GpsProtocolScript.encode_plan(missing_destination, "fastest").is_empty(), "protocol rejects missing destination")

	var decoded: Dictionary = GpsProtocolScript.decode_response('{"success":false,"failure_reason":"unreachable","failed_leg_index":2}')
	_assert(bool(decoded.get("valid", false)), "structured failure response decodes")
	var payload: Dictionary = decoded.get("payload", {}) as Dictionary
	_assert(not bool(payload.get("success", true)), "failure success flag is preserved")
	_assert(str(payload.get("failure_reason", "")) == "unreachable", "failure reason is preserved")
	_assert(int(payload.get("failed_leg_index", -1)) == 2, "failed leg is preserved")
	_assert(not bool(GpsProtocolScript.decode_response("not-json").get("valid", true)), "malformed response is rejected by protocol")

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
