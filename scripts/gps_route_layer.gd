extends Node3D

## Thin Godot adapter for click-to-road GPS routing.
##
## Dependencies:
## - gps_route_model.gd owns waypoint/destination state without UI or transport.
## - gps_protocol.gd owns request encoding.
## - bin/brur-gps-server owns snapping, cost policy and route search in resident native C++.
## - Main owns world origin coordinates; CameraRig supplies the current screen ray.

const GpsRouteModelScript = preload("res://scripts/gps_route_model.gd")
const GpsProtocolScript = preload("res://scripts/gps_protocol.gd")
const EARTH_RADIUS: float = 6378137.0
const START_LON: float = 18.0686
const START_LAT: float = 59.3293
const SERVER_BINARY: String = "res://bin/brur-gps-server"
const GRAPH_PATH: String = "res://world_data/routing.brg"
const SNAP_PATH: String = "res://world_data/routing_snap.brs"
const SERVER_HOST: String = "127.0.0.1"
const SERVER_PORT: int = 47741
const CONNECT_RETRY_SECONDS: float = 0.15
const ROUTING_PREFERENCE_IDS: Array[String] = [
	"fastest",
	"shortest",
	"avoid_small_roads",
	"avoid_major_roads",
]
const ROUTING_PREFERENCE_LABELS: Array[String] = [
	"Fastest",
	"Shortest",
	"Avoid small roads",
	"Avoid major roads",
]

@onready var main: Node3D = get_parent()
@onready var camera_rig: Node3D = get_node("../CameraRig")
@onready var camera: Camera3D = get_node("../CameraRig/Camera3D")

var route_model = GpsRouteModelScript.new()
var player: Node3D
var route_mesh_instance: MeshInstance3D
var route_material: StandardMaterial3D
var target_marker: MeshInstance3D
var status_label: Label
var preference_select: OptionButton
var waypoint_list: ItemList
var remove_waypoint_button: Button
var clear_waypoints_button: Button

var server_path: String = ""
var graph_path: String = ""
var snap_path: String = ""
var server_pid: int = -1
var server_peer: StreamPeerTCP
var receive_buffer: String = ""
var connect_retry_left: float = 0.0
var gps_busy: bool = false

var perf_queries: int = 0
var perf_route_ms: float = 0.0
var perf_route_max_ms: float = 0.0
var perf_settled: int = 0
var perf_relaxed: int = 0
var perf_parse_ms: float = 0.0
var perf_apply_ms: float = 0.0
var perf_points: int = 0
var perf_failures: int = 0
var perf_last_success: bool = false
var perf_last_failure_reason: String = ""
var perf_last_failed_leg: int = -1

func _ready() -> void:
	server_path = ProjectSettings.globalize_path(SERVER_BINARY)
	graph_path = ProjectSettings.globalize_path(GRAPH_PATH)
	snap_path = ProjectSettings.globalize_path(SNAP_PATH)
	_create_route_visuals()
	_create_status_ui()
	call_deferred("_finish_setup")

func _finish_setup() -> void:
	if not FileAccess.file_exists(SERVER_BINARY):
		_set_status("GPS native server missing. Run: bash tools/build_native_gps.sh")
		push_warning("GPS native server missing. Run: bash tools/build_native_gps.sh")
		return
	if not FileAccess.file_exists(GRAPH_PATH) or not FileAccess.file_exists(SNAP_PATH):
		_set_status("GPS data missing: routing.brg / routing_snap.brs")
		return
	_spawn_player()
	_start_native_server()

func _process(delta: float) -> void:
	_update_visual_height()
	_poll_native_server(delta)

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed or not mouse_event.shift_pressed:
		return
	if get_viewport().gui_get_hovered_control() != null:
		return
	if player == null:
		return
	if server_peer == null or server_peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_set_status("GPS native server is not ready yet")
		return
	if gps_busy:
		_set_status("GPS is already calculating a route…")
		return
	var hit: Vector3 = _screen_to_ground(mouse_event.position)
	if not hit.is_finite():
		return
	var absolute: Vector2 = _world_to_absolute(hit)
	if mouse_event.ctrl_pressed or mouse_event.meta_pressed:
		route_model.add_waypoint(absolute)
		_refresh_waypoint_ui()
		if route_model.has_destination():
			_request_current_plan()
		else:
			_set_status("Waypoint %d added — Shift + click destination" % route_model.waypoint_count())
	else:
		route_model.set_destination(absolute)
		_request_current_plan()
	get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if server_peer != null:
		server_peer.disconnect_from_host()
		server_peer = null
	if server_pid > 0:
		OS.kill(server_pid)
		server_pid = -1

func _start_native_server() -> void:
	var args: PackedStringArray = PackedStringArray([
		graph_path,
		snap_path,
		str(SERVER_PORT),
	])
	server_pid = OS.create_process(server_path, args, false)
	if server_pid <= 0:
		_set_status("Could not start native GPS server")
		return
	_set_status("GPS native server starting…")
	server_peer = StreamPeerTCP.new()
	connect_retry_left = 0.0
	_try_connect_server()

func _try_connect_server() -> void:
	if server_peer == null:
		server_peer = StreamPeerTCP.new()
	var status: StreamPeerTCP.Status = server_peer.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED or status == StreamPeerTCP.STATUS_CONNECTING:
		return
	server_peer.disconnect_from_host()
	var error: Error = server_peer.connect_to_host(SERVER_HOST, SERVER_PORT)
	if error != OK:
		connect_retry_left = CONNECT_RETRY_SECONDS

func _poll_native_server(delta: float) -> void:
	if server_peer == null:
		return
	server_peer.poll()
	var status: StreamPeerTCP.Status = server_peer.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTED:
		_read_server_responses()
		if not gps_busy and status_label != null and status_label.text.begins_with("GPS native server"):
			_set_status("GPS ready — Shift+click destination · Cmd/Ctrl+Shift+click waypoint")
		return
	if status == StreamPeerTCP.STATUS_CONNECTING:
		return
	connect_retry_left -= delta
	if connect_retry_left <= 0.0:
		connect_retry_left = CONNECT_RETRY_SECONDS
		_try_connect_server()

func _read_server_responses() -> void:
	var available: int = server_peer.get_available_bytes()
	if available <= 0:
		return
	receive_buffer += server_peer.get_utf8_string(available)
	while true:
		var newline: int = receive_buffer.find("\n")
		if newline < 0:
			break
		var line: String = receive_buffer.substr(0, newline).strip_edges()
		receive_buffer = receive_buffer.substr(newline + 1)
		if line.is_empty():
			continue
		var parse_started: int = Time.get_ticks_usec()
		var parsed: Variant = JSON.parse_string(line)
		perf_parse_ms += float(Time.get_ticks_usec() - parse_started) / 1000.0
		gps_busy = false
		if typeof(parsed) == TYPE_DICTIONARY:
			_apply_route_response(parsed as Dictionary)
		else:
			_set_status("GPS server returned invalid JSON")

func _spawn_player() -> void:
	var scene: PackedScene = load("res://scenes/vehicle.tscn") as PackedScene
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

func _create_route_visuals() -> void:
	route_mesh_instance = MeshInstance3D.new()
	route_mesh_instance.name = "GpsRoute"
	route_material = StandardMaterial3D.new()
	route_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	route_material.albedo_color = Color(0.05, 0.75, 1.0)
	route_material.no_depth_test = true
	route_mesh_instance.material_override = route_material
	add_child(route_mesh_instance)

	target_marker = MeshInstance3D.new()
	target_marker.name = "GpsTarget"
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 80.0
	sphere.height = 160.0
	target_marker.mesh = sphere
	var marker_material: StandardMaterial3D = StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.albedo_color = Color(1.0, 0.35, 0.08)
	target_marker.material_override = marker_material
	target_marker.visible = false
	add_child(target_marker)

func _create_status_ui() -> void:
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.layer = 50
	add_child(canvas)
	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -520.0
	panel.offset_top = 14.0
	panel.offset_right = -14.0
	panel.offset_bottom = 250.0
	canvas.add_child(panel)
	var content: VBoxContainer = VBoxContainer.new()
	panel.add_child(content)
	status_label = Label.new()
	status_label.text = "GPS starting…"
	content.add_child(status_label)
	preference_select = OptionButton.new()
	for label_text in ROUTING_PREFERENCE_LABELS:
		preference_select.add_item(label_text)
	preference_select.selected = 0
	preference_select.tooltip_text = "Routing preference used for every GPS leg"
	preference_select.item_selected.connect(_on_preference_selected)
	content.add_child(preference_select)

	var help: Label = Label.new()
	help.text = "Shift+click destination · Cmd/Ctrl+Shift+click waypoint"
	content.add_child(help)

	waypoint_list = ItemList.new()
	waypoint_list.custom_minimum_size = Vector2(0.0, 80.0)
	waypoint_list.select_mode = ItemList.SELECT_SINGLE
	content.add_child(waypoint_list)

	var buttons: HBoxContainer = HBoxContainer.new()
	content.add_child(buttons)
	remove_waypoint_button = Button.new()
	remove_waypoint_button.text = "Remove selected"
	remove_waypoint_button.pressed.connect(_on_remove_waypoint_pressed)
	buttons.add_child(remove_waypoint_button)
	clear_waypoints_button = Button.new()
	clear_waypoints_button.text = "Clear waypoints"
	clear_waypoints_button.pressed.connect(_on_clear_waypoints_pressed)
	buttons.add_child(clear_waypoints_button)
	_refresh_waypoint_ui()

func _selected_preference() -> String:
	if preference_select == null:
		return ROUTING_PREFERENCE_IDS[0]
	var index: int = clampi(preference_select.selected, 0, ROUTING_PREFERENCE_IDS.size() - 1)
	return ROUTING_PREFERENCE_IDS[index]

func _request_current_plan() -> void:
	if player == null or not route_model.has_destination():
		return
	if server_peer == null or server_peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_set_status("GPS native server is not ready yet")
		return
	if gps_busy:
		_set_status("GPS is already calculating a route…")
		return
	var start_abs: Vector2 = _world_to_absolute(player.global_position)
	var stops: Array[Vector2] = route_model.ordered_stops(start_abs)
	var preference: String = _selected_preference()
	var request: String = GpsProtocolScript.encode_plan(stops, preference)
	if request.is_empty():
		_set_status("GPS route plan has no destination")
		return
	var error: Error = server_peer.put_data(request.to_utf8_buffer())
	if error != OK:
		_set_status("Could not send GPS route plan")
		return
	gps_busy = true
	_set_status("Calculating %s route · %d waypoint(s)…" % [
		preference_select.get_item_text(preference_select.selected),
		route_model.waypoint_count(),
	])

func _on_preference_selected(_index: int) -> void:
	if route_model.has_destination() and not gps_busy:
		_request_current_plan()

func _on_remove_waypoint_pressed() -> void:
	if waypoint_list == null:
		return
	var selected: PackedInt32Array = waypoint_list.get_selected_items()
	if selected.is_empty():
		_set_status("Select a waypoint to remove")
		return
	if route_model.remove_waypoint(int(selected[0])):
		_refresh_waypoint_ui()
		if route_model.has_destination() and not gps_busy:
			_request_current_plan()

func _on_clear_waypoints_pressed() -> void:
	route_model.clear_waypoints()
	_refresh_waypoint_ui()
	if route_model.has_destination() and not gps_busy:
		_request_current_plan()

func _refresh_waypoint_ui() -> void:
	if waypoint_list == null:
		return
	waypoint_list.clear()
	var points: Array[Vector2] = route_model.waypoints()
	for index in range(points.size()):
		var point: Vector2 = points[index]
		waypoint_list.add_item("%d  %.0f, %.0f" % [index + 1, point.x, point.y])
	if remove_waypoint_button != null:
		remove_waypoint_button.disabled = points.is_empty()
	if clear_waypoints_button != null:
		clear_waypoints_button.disabled = points.is_empty()

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
		var failure_reason: String = str(response.get("failure_reason", adapter_error))
		var failed_leg: int = int(response.get("failed_leg_index", -1))
		perf_failures += 1
		perf_last_failure_reason = failure_reason if not failure_reason.is_empty() else "unreachable"
		perf_last_failed_leg = failed_leg
		if failed_leg >= 0:
			_set_status("GPS leg %d failed: %s" % [failed_leg + 1, perf_last_failure_reason])
		else:
			_set_status("GPS error: %s" % perf_last_failure_reason)
		_clear_route_visual()
		perf_apply_ms += float(Time.get_ticks_usec() - apply_started) / 1000.0
		return

	var points_value: Variant = response.get("points", [])
	if typeof(points_value) != TYPE_ARRAY:
		_set_status("GPS returned an invalid polyline")
		perf_apply_ms += float(Time.get_ticks_usec() - apply_started) / 1000.0
		return
	var points: Array = points_value as Array
	perf_points += points.size()
	if points.size() < 2:
		_set_status("GPS route has no drawable geometry")
		perf_apply_ms += float(Time.get_ticks_usec() - apply_started) / 1000.0
		return

	_draw_route(points)
	var start_snap_value: Variant = response.get("start_snap", [])
	if typeof(start_snap_value) == TYPE_ARRAY:
		var start_snap: Array = start_snap_value as Array
		if start_snap.size() >= 2 and player != null:
			var snapped_start: Vector3 = _absolute_to_world(float(start_snap[0]), float(start_snap[1]))
			player.position.x = snapped_start.x
			player.position.z = snapped_start.z

	var target_snap_value: Variant = response.get("target_snap", [])
	if typeof(target_snap_value) == TYPE_ARRAY:
		var target_snap: Array = target_snap_value as Array
		if target_snap.size() >= 2:
			var snapped_target: Vector3 = _absolute_to_world(float(target_snap[0]), float(target_snap[1]))
			target_marker.position.x = snapped_target.x
			target_marker.position.z = snapped_target.z
			target_marker.visible = true

	var distance_km: float = float(response.get("distance_m", 0.0)) / 1000.0
	var minutes: float = float(response.get("travel_time_s", 0.0)) / 60.0
	var preference: String = str(response.get("preference", _selected_preference()))
	var legs_value: Variant = response.get("legs", [])
	var leg_count: int = (legs_value as Array).size() if typeof(legs_value) == TYPE_ARRAY else 1
	_set_status("GPS %s · %d leg(s) · %.1f km · %.0f min · %.1f ms" % [
		preference,
		leg_count,
		distance_km,
		minutes,
		route_ms,
	])
	perf_apply_ms += float(Time.get_ticks_usec() - apply_started) / 1000.0
	print(
		"GPS route | %s | legs %d | %.1f km | %.1f min | %.2f ms | settled %d | relaxed %d | points %d" % [
			preference,
			leg_count,
			distance_km,
			minutes,
			route_ms,
			int(response.get("settled", 0)),
			int(response.get("relaxed", 0)),
			points.size(),
		]
	)

func consume_perf_metrics() -> Dictionary:
	var result: Dictionary = {
		"gps_queries": perf_queries,
		"gps_route_ms": perf_route_ms,
		"gps_route_max_ms": perf_route_max_ms,
		"gps_settled": perf_settled,
		"gps_relaxed": perf_relaxed,
		"gps_parse_ms": perf_parse_ms,
		"gps_apply_ms": perf_apply_ms,
		"gps_points": perf_points,
		"gps_failures": perf_failures,
		"gps_last_success": perf_last_success,
		"gps_failure_reason": perf_last_failure_reason,
		"gps_failed_leg": perf_last_failed_leg,
		"gps_busy": gps_busy,
	}
	perf_queries = 0
	perf_route_ms = 0.0
	perf_route_max_ms = 0.0
	perf_settled = 0
	perf_relaxed = 0
	perf_parse_ms = 0.0
	perf_apply_ms = 0.0
	perf_points = 0
	perf_failures = 0
	perf_last_failure_reason = ""
	perf_last_failed_leg = -1
	return result

func _draw_route(points: Array) -> void:
	var vertices: PackedVector3Array = PackedVector3Array()
	vertices.resize(points.size())
	var count: int = 0
	for value in points:
		if typeof(value) != TYPE_ARRAY:
			continue
		var pair: Array = value as Array
		if pair.size() < 2:
			continue
		var local: Vector3 = _absolute_to_world(float(pair[0]), float(pair[1]))
		vertices[count] = Vector3(local.x, 0.0, local.z)
		count += 1
	vertices.resize(count)
	if count < 2:
		route_mesh_instance.mesh = null
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var route_mesh: ArrayMesh = ArrayMesh.new()
	route_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
	route_mesh_instance.mesh = route_mesh

func _clear_route_visual() -> void:
	route_mesh_instance.mesh = null
	target_marker.visible = false

func _update_visual_height() -> void:
	if camera_rig == null:
		return
	var spacing: float = clampf(float(camera_rig.call("get_distance")) / 6000.0, 4.0, 240.0)
	var route_y: float = spacing * 7.0
	route_mesh_instance.position.y = route_y
	target_marker.position.y = route_y + maxf(90.0, spacing)
	var marker_scale: float = clampf(float(camera_rig.call("get_distance")) / 30000.0, 1.0, 20.0)
	target_marker.scale = Vector3.ONE * marker_scale
	if player != null:
		player.position.y = route_y
		var player_scale: float = clampf(float(camera_rig.call("get_distance")) / 8000.0, 1.0, 40.0)
		player.scale = Vector3.ONE * player_scale

func _screen_to_ground(screen_position: Vector2) -> Vector3:
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	if ray_direction.y >= -0.000001:
		return Vector3(INF, INF, INF)
	var t: float = -ray_origin.y / ray_direction.y
	if t <= 0.0:
		return Vector3(INF, INF, INF)
	return ray_origin + ray_direction * t

func _project_lonlat(lon: float, lat: float) -> Vector2:
	var lat_radians: float = deg_to_rad(clampf(lat, -85.05112878, 85.05112878))
	var x: float = EARTH_RADIUS * deg_to_rad(lon)
	var y: float = EARTH_RADIUS * log(tan(PI / 4.0 + lat_radians / 2.0))
	return Vector2(x, y)

func _world_to_absolute(world_position: Vector3) -> Vector2:
	return Vector2(
		world_position.x + float(main.get("origin_x")),
		-world_position.z + float(main.get("origin_y"))
	)

func _absolute_to_world(x: float, y: float) -> Vector3:
	return Vector3(
		x - float(main.get("origin_x")),
		0.0,
		-(y - float(main.get("origin_y")))
	)

func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text
