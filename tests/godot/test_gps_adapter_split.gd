extends SceneTree

## Headless contracts for the split GPS input, transport-facing protocol and renderer boundaries.
## Dependencies: production gps_input_adapter.gd, gps_protocol.gd and gps_route_renderer.gd only.

const GpsInputAdapterScript = preload("res://scripts/gps_input_adapter.gd")
const GpsProtocolScript = preload("res://scripts/gps_protocol.gd")
const GpsRouteRendererScript = preload("res://scripts/gps_route_renderer.gd")

func _init() -> void:
	_test_input_commands()
	_test_response_protocol()
	_test_renderer_fixture()
	print("godot gps adapter-split tests: OK")
	quit(0)

func _test_input_commands() -> void:
	var destination := InputEventMouseButton.new()
	destination.button_index = MOUSE_BUTTON_LEFT
	destination.pressed = true
	destination.shift_pressed = true
	var command: Dictionary = GpsInputAdapterScript.command_from_mouse(destination, false, Vector2(10.0, 20.0))
	_assert(str(command.get("type", "")) == GpsInputAdapterScript.COMMAND_DESTINATION, "shift-click becomes destination command")
	_assert(command.get("point", Vector2.ZERO) == Vector2(10.0, 20.0), "destination command preserves coordinate")

	var waypoint := InputEventMouseButton.new()
	waypoint.button_index = MOUSE_BUTTON_LEFT
	waypoint.pressed = true
	waypoint.shift_pressed = true
	waypoint.ctrl_pressed = true
	command = GpsInputAdapterScript.command_from_mouse(waypoint, false, Vector2(30.0, 40.0))
	_assert(str(command.get("type", "")) == GpsInputAdapterScript.COMMAND_WAYPOINT, "ctrl-shift-click becomes waypoint command")
	_assert(GpsInputAdapterScript.command_from_mouse(destination, true, Vector2.ONE).is_empty(), "hovered UI blocks route input")
	_assert(GpsInputAdapterScript.command_from_mouse(destination, false, Vector2(INF, INF)).is_empty(), "invalid coordinate is rejected")

func _test_response_protocol() -> void:
	var success: Dictionary = GpsProtocolScript.decode_response('{"success":true,"points":[[1,2],[3,4]]}')
	_assert(bool(success.get("valid", false)), "valid structured response is accepted")
	var payload: Dictionary = success.get("payload", {}) as Dictionary
	_assert(bool(payload.get("success", false)), "success flag survives response conversion")
	_assert((payload.get("points", []) as Array).size() == 2, "route points survive response conversion")

	var failure: Dictionary = GpsProtocolScript.decode_response('{"success":false,"failure_reason":"unreachable","failed_leg_index":1}')
	_assert(bool(failure.get("valid", false)), "failure payload is still a valid protocol response")
	payload = failure.get("payload", {}) as Dictionary
	_assert(str(payload.get("failure_reason", "")) == "unreachable", "failure reason stays structured")
	_assert(int(payload.get("failed_leg_index", -1)) == 1, "failed leg stays structured")
	_assert(str(GpsProtocolScript.decode_response("broken").get("error", "")) == "invalid_response", "malformed JSON fails at protocol boundary")

func _test_renderer_fixture() -> void:
	var renderer: Node3D = GpsRouteRendererScript.new()
	renderer.call("setup", Callable(self, "_to_world"))
	var response := {
		"success": true,
		"points": [[10.0, 20.0], [15.0, 25.0], [20.0, 30.0]],
		"target_snap": [20.0, 30.0],
	}
	_assert(bool(renderer.call("apply_response", response)), "renderer accepts fixture route without live server")
	_assert(int(renderer.call("rendered_point_count")) == 3, "renderer consumes all valid fixture points")
	_assert(not bool(renderer.call("apply_response", {"success": false, "failure_reason": "unreachable"})), "failed route clears renderer")
	_assert(int(renderer.call("rendered_point_count")) == 0, "failed route leaves no route geometry")
	renderer.free()

func _to_world(x: float, y: float) -> Vector3:
	return Vector3(x, 0.0, -y)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("gps adapter-split test failed: " + message)
	quit(1)
