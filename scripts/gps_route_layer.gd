extends Node3D

## Composes GPS route state/rendering with the single player vehicle and its manual/GPS control ownership.
##
## Dependencies:
## - GpsClient owns native process/TCP lifecycle and response delivery.
## - GpsRouteModel owns destination/waypoint/preference state.
## - GpsRouteRenderer/GpsRouteUi own GPS presentation; the player vehicle owns motion state/dynamics.
## - Main exposes WorldCoordinates; CameraRig receives the player as an explicit follow target.

signal teleport_state_changed(armed: bool)

const GpsClientScript = preload("res://scripts/gps_client.gd")
const GpsInputAdapterScript = preload("res://scripts/gps_input_adapter.gd")
const GpsProtocolScript = preload("res://scripts/gps_protocol.gd")
const GpsRouteModelScript = preload("res://scripts/gps_route_model.gd")
const GpsRouteRendererScript = preload("res://scripts/gps_route_renderer.gd")
const GpsRouteUiScript = preload("res://scripts/gps_route_ui.gd")
const EARTH_RADIUS: float = 6378137.0
const START_LON: float = 18.0686
const START_LAT: float = 59.3293

@export var main_path: NodePath
@export var camera_rig_path: NodePath
@export var camera_path: NodePath

var route_model = GpsRouteModelScript.new()
var player: Node3D
var gps_client: Node
var route_renderer: Node3D
var route_ui: CanvasLayer

var _main: Node3D
var _camera_rig: Node3D
var _camera: Camera3D
var _player_controller: Node
var _route_follower: Node
var _follow_enabled: bool = false
var _teleport_armed: bool = false
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
	if _main == null and not main_path.is_empty():
		_main = get_node(main_path) as Node3D
	if _camera_rig == null and not camera_rig_path.is_empty():
		_camera_rig = get_node(camera_rig_path) as Node3D
	if _camera == null and not camera_path.is_empty():
		_camera = get_node(camera_path) as Camera3D
	call_deferred("_finish_setup")

func _process(delta: float) -> void:
	if gps_client != null:
		gps_client.call("poll", delta)
	_update_driving_input_mode()
	_update_visual_height()

func _input(event: InputEvent) -> void:
	if _camera == null or player == null:
		return
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed:
		return
	if get_viewport().gui_get_hovered_control() != null:
		return
	var hit: Vector3 = _screen_to_ground(mouse_event.position)
	if not hit.is_finite():
		return
	if _teleport_armed:
		if teleport_player_to_world(hit):
			set_teleport_armed(false)
			_set_status("Player vehicle teleported")
			get_viewport().set_input_as_handled()
		return
	if not mouse_event.shift_pressed:
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

func get_player_vehicle() -> Node3D:
	return player

func set_teleport_armed(armed: bool) -> void:
	if _teleport_armed == armed:
		return
	_teleport_armed = armed
	teleport_state_changed.emit(armed)

func is_teleport_armed() -> bool:
	return _teleport_armed

func teleport_player_to_world(world_position: Vector3) -> bool:
	if player == null or not world_position.is_finite():
		return false
	var target := Vector3(world_position.x, player.global_position.y, world_position.z)
	player.call("set_world_position", target)
	player.call("stop")
	_update_visual_height()
	return true

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
		str(route_ui.call("preference_label", route_model.preference())),
		route_model.waypoint_count(),
	])
	return true

func set_follow_enabled(enabled: bool) -> bool:
	if _route_follower == null:
		return false
	if not bool(_route_follower.call("set_follow_enabled", enabled)):
		if enabled:
			_set_status("No drivable GPS route is active")
		return false
	_follow_enabled = enabled
	if route_ui != null:
		route_ui.call("set_follow_enabled", enabled)
	if enabled:
		_set_status("GPS follow ON — press W/A/S/D or Space to take manual control")
	else:
		_set_status("GPS follow OFF — manual driving")
	return true

func is_follow_enabled() -> bool:
	return _follow_enabled

# Compatibility bridge for existing callers while the public API lands.
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
	route_ui.connect("follow_changed", _on_follow_changed)
	route_ui.call("set_preference", route_model.preference())
	route_ui.call("set_follow_available", false)
	_refresh_waypoint_ui()

func _finish_setup() -> void:
	if _setup_started or _main == null or _camera_rig == null or _camera == null or gps_client == null:
		return
	_setup_started = true
	_spawn_player()
	gps_client.call("start")

func _apply_input_command(command: Dictionary) -> void:
	var point: Vector2 = command.get("point", Vector2(INF, INF))
	var command_type: String = str(command.get("type", ""))
	if command_type == GpsInputAdapterScript.COMMAND_WAYPOINT:
		add_waypoint(point)
	elif command_type == GpsInputAdapterScript.COMMAND_DESTINATION:
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

func _on_follow_changed(enabled: bool) -> void:
	if not set_follow_enabled(enabled) and route_ui != null:
		route_ui.call("set_follow_enabled", false)

func _on_manual_vehicle_input() -> void:
	if _follow_enabled:
		set_follow_enabled(false)

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
		_clear_follow_route()
		if perf_last_failed_leg >= 0:
			_set_status("GPS leg %d failed: %s" % [perf_last_failed_leg + 1, perf_last_failure_reason])
		else:
			_set_status("GPS error: %s" % perf_last_failure_reason)
		perf_apply_ms += float(Time.get_ticks_usec() - apply_started) / 1000.0
		return

	if not bool(route_renderer.call("apply_response", response)):
		_clear_follow_route()
		_set_status("GPS returned an invalid polyline")
		perf_apply_ms += float(Time.get_ticks_usec() - apply_started) / 1000.0
		return
	perf_points += int(route_renderer.call("rendered_point_count"))
	_install_follow_route(response)
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

func _install_follow_route(response: Dictionary) -> void:
	if _route_follower == null:
		return
	var points_value: Variant = response.get("points", [])
	if typeof(points_value) != TYPE_ARRAY:
		_clear_follow_route()
		return
	var world_points := PackedVector3Array()
	for value in points_value as Array:
		if typeof(value) != TYPE_ARRAY:
			continue
		var pair: Array = value as Array
		if pair.size() < 2:
			continue
		var world_point: Vector3 = _absolute_to_world(float(pair[0]), float(pair[1]))
		if world_point.is_finite():
			world_points.append(world_point)
	_route_follower.call("set_route", world_points)
	var available: bool = world_points.size() >= 2
	route_ui.call("set_follow_available", available)
	if _follow_enabled:
		if not bool(_route_follower.call("set_follow_enabled", true)):
			_follow_enabled = false
			route_ui.call("set_follow_enabled", false)

func _clear_follow_route() -> void:
	_follow_enabled = false
	if _route_follower != null:
		_route_follower.call("set_follow_enabled", false)
		_route_follower.call("clear_route")
	if route_ui != null:
		route_ui.call("set_follow_available", false)
		route_ui.call("set_follow_enabled", false)

func _on_protocol_error(error: String) -> void:
	perf_failures += 1
	perf_last_success = false
	perf_last_failure_reason = error
	perf_last_failed_leg = -1
	_clear_follow_route()
	_set_status("GPS server returned invalid response")

func _on_client_ready_changed(ready: bool) -> void:
	if ready:
		_set_status("GPS ready — zoom in to drive · Shift+click destination · Cmd/Ctrl+Shift+click waypoint")

func consume_perf_metrics() -> Dictionary:
	var client_metrics: Dictionary = {}
	if gps_client != null:
		client_metrics = gps_client.call("consume_perf_metrics") as Dictionary
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
	var scene := load("res://scenes/player_vehicle.tscn") as PackedScene
	if scene == null:
		push_error("Could not load player vehicle scene")
		return
	player = scene.instantiate() as Node3D
	add_child(player)
	var projected: Vector2 = _project_lonlat(START_LON, START_LAT)
	var spawn_position: Vector3 = _absolute_to_world(projected.x, projected.y)
	player.call("set_world_position", spawn_position)
	_player_controller = player.get_node_or_null("PlayerVehicleController")
	_route_follower = player.get_node_or_null("VehicleRouteFollower")
	if _player_controller != null:
		_player_controller.connect("manual_input_detected", _on_manual_vehicle_input)
	if _camera_rig.has_method("set_follow_target"):
		_camera_rig.call("set_follow_target", player)
	_update_visual_height()

func _update_driving_input_mode() -> void:
	if _player_controller == null or _camera_rig == null:
		return
	var driving_view: bool = bool(_camera_rig.call("is_driving_view")) if _camera_rig.has_method("is_driving_view") else true
	_player_controller.set("enabled", driving_view)

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

func _world_coordinates():
	if _main == null:
		return null
	return _main.call("get_world_coordinates")

func _world_to_absolute(world_position: Vector3) -> Vector2:
	var coordinates = _world_coordinates()
	if coordinates == null:
		return Vector2(INF, INF)
	return coordinates.world_to_absolute(world_position)

func _absolute_to_world(x: float, y: float) -> Vector3:
	var coordinates = _world_coordinates()
	if coordinates == null:
		return Vector3(INF, INF, INF)
	return coordinates.absolute_to_world(Vector2(x, y))

func _set_status(text: String) -> void:
	if route_ui != null:
		route_ui.call("set_status", text)
