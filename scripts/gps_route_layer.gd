extends Node3D

## Composes the Godot GPS client, route state, rendering, input and UI boundaries.
##
## Dependencies:
## - GpsClient owns native process/TCP lifecycle and response delivery.
## - GpsRouteModel owns destination/waypoint/preference state.
## - GpsRouteRenderer owns route/target visuals; GpsRouteUi owns controls/status.
## - Main explicitly supplies world origin and camera dependencies through setup().

const GpsClientScript = preload("res://scripts/gps_client.gd")
const GpsInputAdapterScript = preload("res://scripts/gps_input_adapter.gd")
const GpsProtocolScript = preload("res://scripts/gps_protocol.gd")
const GpsRouteModelScript = preload("res://scripts/gps_route_model.gd")
const GpsRouteRendererScript = preload("res://scripts/gps_route_renderer.gd")
const GpsRouteUiScript = preload("res://scripts/gps_route_ui.gd")
const EARTH_RADIUS: float = 6378137.0
const START_LON: float = 18.0686
const START_LAT: float = 59.3293

var route_model = GpsRouteModelScript.new()
var player: Node3D
var gps_client: Node
var route_renderer: Node3D
var route_ui: CanvasLayer

var _main: Node3D
var _camera_rig: Node3D
var _camera: Camera3D
var _setup_started: bool = false

var perf_queries: int = 0
var perf_route_ms: float = 0.0
var perf_route_max_ms: float = 0.0
var perf_settled: int = 0
var perf_relaxed: int = 0
var perf_apply_ms: float = 0.0
var perf_points: int = 0
var perf_failures: int = 0
var perf_last_success: bool = false
var perf_last_failure_reason: String = ""
var perf_last_failed_leg: int = -1

func setup(main_owner: Node3D, camera_rig: Node3D, camera: Camera3D) -> void:
	_main = main_owner
	_camera_rig = camera_rig
	_camera = camera
	if is_inside_tree():
		call_deferred("_finish_setup")

func _ready() -> void:
	_create_modules()
	call_deferred("_finish_setup")

func _process(delta: float) -> void:
	if gps_client != null:
		gps_client.call("poll", delta)
	_update_visual_height()

func _input(event: InputEvent) -> void:
	if _camera == null or player == null:
		return
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed or not mouse_event.shift_pressed:
		return
	var gui_blocked: bool = get_viewport().gui_get_hovered_control() != null
	if gui_blocked:
		return
	var hit: Vector3 = _screen_to_ground(mouse_event.position)
	if not hit.is_finite():
		return
	var command: Dictionary = GpsInputAdapterScript.command_from_mouse(event, false, _world_to_absolute(hit))
	if command.is_empty():
		return
	if gps_client == null or not bool(gps_client.call("is_ready")):
		_set_status("GPS native server is not ready yet")
		return
	if bool(gps_client.call("is_busy")):
		_set_status("GPS is already calculating a route…")
		return
	_apply_input_command(command)
	get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if gps_client != null:
		gps_client.call("stop")

func set_destination(point: Vector2) -> bool:
	if not point.is_finite():
		return false
	route_model.set_destination(point)
	request_current_plan()
	return true

func add_waypoint(point: Vector2) -> bool:
	if not point.is_finite():
		return false
	route_model.add_waypoint(point)
	_refresh_waypoint_ui()
	if route_model.has_destination():
		request_current_plan()
	else:
		_set_status("Waypoint %d added — Shift + click destination" % route_model.waypoint_count())
	return true

func request_current_plan() -> bool:
	if player == null or not route_model.has_destination():
		return false
	if gps_client == null or not bool(gps_client.call("is_ready")):
		_set_status("GPS native server is not ready yet")
		return false
	if bool(gps_client.call("is_busy")):
		_set_status("GPS is already calculating a route…")
		return false
	var start_abs: Vector2 = _world_to_absolute(player.global_position)
	var request: String = GpsProtocolScript.encode_plan(route_model.ordered_stops(start_abs), route_model.preference())
	if request.is_empty():
		_set_status("GPS route plan has no destination")
		return false
	if not bool(gps_client.call("send_request", request)):
		_set_status("Could not send GPS route plan")
		return false
	_set_status("Calculating %s route · %d waypoint(s)…" % [
		route_ui.call("preference_label", route_model.preference()),
		route_model.waypoint_count(),
	])
	return true

# Compatibility bridge for existing adapters/tests while callers migrate to the public API.
func _request_current_plan() -> void:
	request_current_plan()

func _create_modules() -> void:
	if gps_client != null:
		return
	gps_client = GpsClientScript.new()
	gps_client.name = "GpsClient"
	add_child(gps_client)
	gps_client.connect("ready_changed", _on_client_ready_changed)
	gps_client.connect("response_received", _apply_route_response)
	gps_client.connect("protocol_error", _on_protocol_error)
	gps_client.connect("transport_status", _set_status)

	route_renderer = GpsRouteRendererScript.new()
	route_renderer.name = "GpsRouteRenderer"
	add_child(route_renderer)
	route_renderer.call("setup", Callable(self, "_absolute_to_world"))

	route_ui = GpsRouteUiScript.new()
	route_ui.name = "GpsRouteUi"
	add_child(route_ui)
	route_ui.connect("preference_selected", _on_preference_selected)
	route_ui.connect("remove_waypoint_requested", _on_remove_waypoint_requested)
	route_ui.connect("clear_waypoints_requested", _on_clear_waypoints_requested)
	route_ui.call("set_preference", route_model.preference())
	_refresh_waypoint_ui()

func _finish_setup() -> void:
	if _setup_started or _main == null or _camera_rig == null or _camera == null or gps_client == null:
		return
	_setup_started = true
	_spawn_player()
	gps_client.call("start")

func _apply_input_command(command: Dictionary) -> void:
	var point: Vector2 = command.get("point", Vector2(INF, INF)) as Vector2
	match str(command.get("type", "")):
		GpsInputAdapterScript.COMMAND_WAYPOINT:
			add_waypoint(point)
		GpsInputAdapterScript.COMMAND_DESTINATION:
			set_destination(point)

func _on_preference_selected(preference: String) -> void:
	if not route_model.set_preference(preference):
		return
	if route_model.has_destination() and gps_client != null and not bool(gps_client.call("is_busy")):
		request_current_plan()

func _on_remove_waypoint_requested(index: int) -> void:
	if route_model.remove_waypoint(index):
		_refresh_waypoint_ui()
		if route_model.has_destination():
			request_current_plan()

func _on_clear_waypoints_requested() -> void:
	route_model.clear_waypoints()
	_refresh_waypoint_ui()
	if route_model.has_destination():
		request_current_plan()

func _refresh_waypoint_ui() -> void:
	if route_ui != null:
		route_ui.call("set_waypoints", route_model.waypoints())

func _apply_route_response(response: Dictionary) -> void:
	var apply_started: int = Time.get_ticks_usec()
	perf_queries += 1
	var route_ms: float = float(response.get("route_ms", 0.0))
	perf_route_ms += route_ms
	perf_route_max_ms = maxf(perf_route_max_ms, route_ms)
	perf_settled += int(response.get("settled", 0))
	perf_relaxed += int(response.get("relaxed", 0))
	perf_last_success = bool(response.get("success", false))

	if not perf_last_success:
		var adapter_error: String = str(response.get("adapter_error", ""))
		perf_last_failure_reason = str(response.get("failure_reason", adapter_error))
		if perf_last_failure_reason.is_empty():
			perf_last_failure_reason = "unreachable"
		perf_last_failed_leg = int(response.get("failed_leg_index", -1))
		perf_failures += 1
		route_renderer.call("clear")
		if perf_last_failed_leg >= 0:
			_set_status("GPS leg %d failed: %s" % [perf_last_failed_leg + 1, perf_last_failure_reason])
		else:
			_set_status("GPS error: %s" % perf_last_failure_reason)
		perf_apply_ms += float(Time.get_ticks_usec() - apply_started) / 1000.0
		return

	if not bool(route_renderer.call("apply_response", response)):
		_set_status("GPS returned an invalid polyline")
		perf_apply_ms += float(Time.get_ticks_usec() - apply_started) / 1000.0
		return
	perf_points += int(route_renderer.call("rendered_point_count"))
	_apply_start_snap(response)
	var legs_value: Variant = response.get("legs", [])
	var leg_count: int = (legs_value as Array).size() if typeof(legs_value) == TYPE_ARRAY else 1
	_set_status("GPS %s · %d leg(s) · %.1f km · %.0f min · %.1f ms" % [
		str(response.get("preference", route_model.preference())),
		leg_count,
		float(response.get("distance_m", 0.0)) / 1000.0,
		float(response.get("travel_time_s", 0.0)) / 60.0,
		route_ms,
	])
	perf_apply_ms += float(Time.get_ticks_usec() - apply_started) / 1000.0
	print("GPS route | %s | legs %d | %.1f km | %.1f min | %.2f ms | settled %d | relaxed %d | points %d" % [
		str(response.get("preference", route_model.preference())),
		leg_count,
		float(response.get("distance_m", 0.0)) / 1000.0,
		float(response.get("travel_time_s", 0.0)) / 60.0,
		route_ms,
		int(response.get("settled", 0)),
		int(response.get("relaxed", 0)),
		int(route_renderer.call("rendered_point_count")),
	])

func _apply_start_snap(response: Dictionary) -> void:
	var start_value: Variant = response.get("start_snap", [])
	if typeof(start_value) != TYPE_ARRAY or player == null:
		return
	var snap: Array = start_value as Array
	if snap.size() < 2:
		return
	var snapped_start: Vector3 = _absolute_to_world(float(snap[0]), float(snap[1]))
	player.position.x = snapped_start.x
	player.position.z = snapped_start.z

func _on_protocol_error(error: String) -> void:
	perf_failures += 1
	perf_last_success = false
	perf_last_failure_reason = error
	perf_last_failed_leg = -1
	_set_status("GPS server returned invalid response")

func _on_client_ready_changed(ready: bool) -> void:
	if ready:
		_set_status("GPS ready — Shift+click destination · Cmd/Ctrl+Shift+click waypoint")

func consume_perf_metrics() -> Dictionary:
	var client_metrics: Dictionary = gps_client.call("consume_perf_metrics") as Dictionary if gps_client != null else {}
	var result: Dictionary = {
		"gps_queries": perf_queries,
		"gps_route_ms": perf_route_ms,
		"gps_route_max_ms": perf_route_max_ms,
		"gps_settled": perf_settled,
		"gps_relaxed": perf_relaxed,
		"gps_parse_ms": float(client_metrics.get("gps_parse_ms", 0.0)),
		"gps_apply_ms": perf_apply_ms,
		"gps_points": perf_points,
		"gps_failures": perf_failures,
		"gps_last_success": perf_last_success,
		"gps_failure_reason": perf_last_failure_reason,
		"gps_failed_leg": perf_last_failed_leg,
		"gps_busy": bool(gps_client.call("is_busy")) if gps_client != null else false,
	}
	perf_queries = 0
	perf_route_ms = 0.0
	perf_route_max_ms = 0.0
	perf_settled = 0
	perf_relaxed = 0
	perf_apply_ms = 0.0
	perf_points = 0
	perf_failures = 0
	perf_last_failure_reason = ""
	perf_last_failed_leg = -1
	return result

func _spawn_player() -> void:
	var scene := load("res://scenes/vehicle.tscn") as PackedScene
	if scene == null:
		push_error("Could not load player vehicle scene")
		return
	player = scene.instantiate() as Node3D
	player.set("vehicle_id", &"player")
	player.set("active", false)
	add_child(player)
	var projected: Vector2 = _project_lonlat(START_LON, START_LAT)
	player.position = _absolute_to_world(projected.x, projected.y)
	_update_visual_height()

func _update_visual_height() -> void:
	if _camera_rig == null or route_renderer == null:
		return
	var camera_distance: float = float(_camera_rig.call("get_distance"))
	route_renderer.call("update_height", camera_distance)
	if player != null:
		player.position.y = float(route_renderer.call("route_height"))
		var player_scale: float = clampf(camera_distance / 8000.0, 1.0, 40.0)
		player.scale = Vector3.ONE * player_scale

func _screen_to_ground(screen_position: Vector2) -> Vector3:
	var ray_origin: Vector3 = _camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = _camera.project_ray_normal(screen_position)
	if ray_direction.y >= -0.000001:
		return Vector3(INF, INF, INF)
	var t: float = -ray_origin.y / ray_direction.y
	if t <= 0.0:
		return Vector3(INF, INF, INF)
	return ray_origin + ray_direction * t

func _project_lonlat(lon: float, lat: float) -> Vector2:
	var lat_radians: float = deg_to_rad(clampf(lat, -85.05112878, 85.05112878))
	return Vector2(
		EARTH_RADIUS * deg_to_rad(lon),
		EARTH_RADIUS * log(tan(PI / 4.0 + lat_radians / 2.0))
	)

func _world_to_absolute(world_position: Vector3) -> Vector2:
	if _main == null:
		return Vector2(INF, INF)
	return Vector2(
		world_position.x + float(_main.get("origin_x")),
		-world_position.z + float(_main.get("origin_y"))
	)

func _absolute_to_world(x: float, y: float) -> Vector3:
	if _main == null:
		return Vector3(INF, INF, INF)
	return Vector3(
		x - float(_main.get("origin_x")),
		0.0,
		-(y - float(_main.get("origin_y")))
	)

func _set_status(text: String) -> void:
	if route_ui != null:
		route_ui.call("set_status", text)
