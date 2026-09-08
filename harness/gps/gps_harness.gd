extends Node3D

## Isolated runtime harness for the production GPS model, protocol, client and renderer.
##
## Dependencies:
## - Uses the same scripts/gps_* production modules as the game.
## - Fixture responses exercise rendering without a server; R uses the real native Sweden route path when data exists.

const GpsClientScript = preload("res://scripts/gps_client.gd")
const GpsProtocolScript = preload("res://scripts/gps_protocol.gd")
const GpsRouteModelScript = preload("res://scripts/gps_route_model.gd")
const GpsRouteRendererScript = preload("res://scripts/gps_route_renderer.gd")

const STOCKHOLM_START := Vector2(2011387.351347343, 8251904.234165725)
const STOCKHOLM_TARGET := Vector2(2003851.021820639, 8258606.904683385)

@onready var status_label: Label = $Ui/Panel/Status

var model = GpsRouteModelScript.new()
var renderer: Node3D
var client: Node
var _pending_real_request: bool = false

func _ready() -> void:
	renderer = GpsRouteRendererScript.new()
	renderer.name = "GpsRouteRenderer"
	add_child(renderer)
	renderer.call("setup", Callable(self, "_absolute_to_harness"))
	renderer.call("update_height", 12000.0)

	client = GpsClientScript.new()
	client.name = "GpsClient"
	add_child(client)
	client.connect("ready_changed", _on_client_ready_changed)
	client.connect("response_received", _on_real_response)
	client.connect("protocol_error", _on_protocol_error)
	client.connect("transport_status", _set_status)
	show_direct_fixture()

func _process(delta: float) -> void:
	client.call("poll", delta)

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			show_direct_fixture()
		KEY_2:
			show_waypoint_fixture()
		KEY_3:
			show_failure_fixture()
		KEY_R:
			request_real_sweden_route()

func show_direct_fixture() -> void:
	model.clear_waypoints()
	model.set_destination(STOCKHOLM_TARGET)
	_apply_fixture([
		[STOCKHOLM_START.x, STOCKHOLM_START.y],
		[STOCKHOLM_START.x - 2500.0, STOCKHOLM_START.y + 1600.0],
		[STOCKHOLM_TARGET.x, STOCKHOLM_TARGET.y],
	], STOCKHOLM_TARGET, "Fixture direct route")

func show_waypoint_fixture() -> void:
	var waypoint := Vector2(STOCKHOLM_START.x - 3000.0, STOCKHOLM_START.y + 2500.0)
	model.clear_waypoints()
	model.add_waypoint(waypoint)
	model.set_destination(STOCKHOLM_TARGET)
	_apply_fixture([
		[STOCKHOLM_START.x, STOCKHOLM_START.y],
		[waypoint.x, waypoint.y],
		[STOCKHOLM_TARGET.x, STOCKHOLM_TARGET.y],
	], STOCKHOLM_TARGET, "Fixture waypoint route")

func show_failure_fixture() -> void:
	var response := {
		"success": false,
		"failure_reason": "unreachable",
		"failed_leg_index": 0,
		"points": [],
	}
	renderer.call("apply_response", response)
	_set_status("Fixture failure: unreachable")

func request_real_sweden_route() -> void:
	model.clear_waypoints()
	model.set_destination(STOCKHOLM_TARGET)
	_pending_real_request = true
	if bool(client.call("is_ready")):
		_send_real_request()
	else:
		client.call("start")

func _send_real_request() -> void:
	if not _pending_real_request:
		return
	var request: String = GpsProtocolScript.encode_plan(model.ordered_stops(STOCKHOLM_START), model.preference())
	if bool(client.call("send_request", request)):
		_pending_real_request = false
		_set_status("Real Sweden route requested…")

func _on_client_ready_changed(ready: bool) -> void:
	if ready and _pending_real_request:
		_send_real_request()

func _on_real_response(response: Dictionary) -> void:
	if bool(renderer.call("apply_response", response)):
		_set_status("Real route: %.1f km · %.1f ms" % [
			float(response.get("distance_m", 0.0)) / 1000.0,
			float(response.get("route_ms", 0.0)),
		])
	else:
		_set_status("Real route failed: %s" % str(response.get("failure_reason", "unreachable")))

func _on_protocol_error(error: String) -> void:
	_set_status("Protocol error: " + error)

func _apply_fixture(points: Array, target: Vector2, label: String) -> void:
	var response := {
		"success": true,
		"points": points,
		"target_snap": [target.x, target.y],
	}
	renderer.call("apply_response", response)
	_set_status(label + " · 1 direct · 2 waypoint · 3 failure · R real Sweden")

func _absolute_to_harness(x: float, y: float) -> Vector3:
	return Vector3(x - STOCKHOLM_START.x, 0.0, -(y - STOCKHOLM_START.y))

func _set_status(text: String) -> void:
	status_label.text = text
