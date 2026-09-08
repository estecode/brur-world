extends Node3D

## Thin Godot adapter for click-to-road GPS routing.
##
## Dependencies:
## - bin/brur-gps-route owns snapping and route search in native C++.
## - Main owns world origin coordinates; CameraRig supplies the current screen ray.
## - Godot only launches the native query on a worker thread and renders its polyline.

const EARTH_RADIUS: float = 6378137.0
const START_LON: float = 18.0686
const START_LAT: float = 59.3293
const ROUTE_BINARY: String = "res://bin/brur-gps-route"
const GRAPH_PATH: String = "res://world_data/routing.brg"
const SNAP_PATH: String = "res://world_data/routing_snap.brs"

@onready var main: Node3D = get_parent()
@onready var camera_rig: Node3D = get_node("../CameraRig")
@onready var camera: Camera3D = get_node("../CameraRig/Camera3D")

var player: Node3D
var route_mesh_instance: MeshInstance3D
var target_marker: MeshInstance3D
var status_label: Label
var route_thread: Thread
var binary_path: String = ""
var graph_path: String = ""
var snap_path: String = ""

var perf_queries: int = 0
var perf_route_ms: float = 0.0
var perf_route_max_ms: float = 0.0
var perf_settled: int = 0
var perf_relaxed: int = 0
var perf_last_success: bool = false

func _ready() -> void:
	binary_path = ProjectSettings.globalize_path(ROUTE_BINARY)
	graph_path = ProjectSettings.globalize_path(GRAPH_PATH)
	snap_path = ProjectSettings.globalize_path(SNAP_PATH)
	_create_route_visuals()
	_create_status_ui()
	call_deferred("_finish_setup")

func _finish_setup() -> void:
	if not FileAccess.file_exists(ROUTE_BINARY):
		_set_status("GPS native binary missing. Run: bash tools/build_native_gps.sh")
		push_warning("GPS native binary missing. Run: bash tools/build_native_gps.sh")
		return
	if not FileAccess.file_exists(GRAPH_PATH) or not FileAccess.file_exists(SNAP_PATH):
		_set_status("GPS data missing: routing.brg / routing_snap.brs")
		return
	_spawn_player()
	_set_status("GPS ready — Shift + left click a road to route from the player")

func _process(_delta: float) -> void:
	_update_visual_height()
	if route_thread != null and not route_thread.is_alive():
		var response: Variant = route_thread.wait_to_finish()
		route_thread = null
		if typeof(response) == TYPE_DICTIONARY:
			_apply_route_response(response as Dictionary)
		else:
			_set_status("GPS query failed")

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed or not mouse_event.shift_pressed:
		return
	if player == null:
		return
	if route_thread != null:
		_set_status("GPS is already calculating a route…")
		return
	var hit: Vector3 = _screen_to_ground(mouse_event.position)
	if not hit.is_finite():
		return
	_request_route(hit)
	get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if route_thread != null:
		route_thread.wait_to_finish()
		route_thread = null

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
	panel.offset_bottom = 58.0
	canvas.add_child(panel)
	status_label = Label.new()
	status_label.text = "GPS starting…"
	panel.add_child(status_label)

func _request_route(target_world: Vector3) -> void:
	var start_abs: Vector2 = _world_to_absolute(player.global_position)
	var target_abs: Vector2 = _world_to_absolute(target_world)
	var args: PackedStringArray = PackedStringArray([
		str(start_abs.x),
		str(start_abs.y),
		str(target_abs.x),
		str(target_abs.y),
		graph_path,
		snap_path,
	])
	route_thread = Thread.new()
	var error: Error = route_thread.start(_run_native_route.bind(args))
	if error != OK:
		route_thread = null
		_set_status("Could not start GPS worker")
		return
	_set_status("Calculating GPS route…")

func _run_native_route(args: PackedStringArray) -> Dictionary:
	var output: Array = []
	var exit_code: int = OS.execute(binary_path, args, output, false, false)
	var text: String = ""
	for chunk in output:
		text += String(chunk)
	var parsed: Variant = JSON.parse_string(text.strip_edges())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {
			"success": false,
			"adapter_error": "native output was not JSON",
			"exit_code": exit_code,
		}
	var result: Dictionary = parsed as Dictionary
	result["exit_code"] = exit_code
	return result

func _apply_route_response(response: Dictionary) -> void:
	perf_queries += 1
	var route_ms: float = float(response.get("route_ms", 0.0))
	perf_route_ms += route_ms
	perf_route_max_ms = maxf(perf_route_max_ms, route_ms)
	perf_settled += int(response.get("settled", 0))
	perf_relaxed += int(response.get("relaxed", 0))
	perf_last_success = bool(response.get("success", false))

	if not perf_last_success:
		_set_status("No drivable route found")
		_clear_route_visual()
		return

	var points_value: Variant = response.get("points", [])
	if typeof(points_value) != TYPE_ARRAY:
		_set_status("GPS returned an invalid polyline")
		return
	var points: Array = points_value as Array
	if points.size() < 2:
		_set_status("GPS route has no drawable geometry")
		return

	_draw_route(points)
	var start_snap: Array = response.get("start_snap", []) as Array
	if start_snap.size() >= 2 and player != null:
		var snapped_start: Vector3 = _absolute_to_world(float(start_snap[0]), float(start_snap[1]))
		player.position.x = snapped_start.x
		player.position.z = snapped_start.z

	var target_snap: Array = response.get("target_snap", []) as Array
	if target_snap.size() >= 2:
		var snapped_target: Vector3 = _absolute_to_world(float(target_snap[0]), float(target_snap[1]))
		target_marker.position.x = snapped_target.x
		target_marker.position.z = snapped_target.z
		target_marker.visible = true

	var distance_km: float = float(response.get("distance_m", 0.0)) / 1000.0
	var minutes: float = float(response.get("travel_time_s", 0.0)) / 60.0
	_set_status("GPS %.1f km · %.0f min · %.1f ms" % [distance_km, minutes, route_ms])
	print(
		"GPS route | %.1f km | %.1f min | %.2f ms | settled %d | relaxed %d" % [
			distance_km,
			minutes,
			route_ms,
			int(response.get("settled", 0)),
			int(response.get("relaxed", 0)),
		]
	)

func consume_perf_metrics() -> Dictionary:
	var result: Dictionary = {
		"gps_queries": perf_queries,
		"gps_route_ms": perf_route_ms,
		"gps_route_max_ms": perf_route_max_ms,
		"gps_settled": perf_settled,
		"gps_relaxed": perf_relaxed,
		"gps_last_success": perf_last_success,
		"gps_busy": route_thread != null,
	}
	perf_queries = 0
	perf_route_ms = 0.0
	perf_route_max_ms = 0.0
	perf_settled = 0
	perf_relaxed = 0
	return result

func _draw_route(points: Array) -> void:
	var route_mesh: ImmediateMesh = ImmediateMesh.new()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.05, 0.75, 1.0)
	material.no_depth_test = true
	route_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
	for value in points:
		if typeof(value) != TYPE_ARRAY:
			continue
		var pair: Array = value as Array
		if pair.size() < 2:
			continue
		var local: Vector3 = _absolute_to_world(float(pair[0]), float(pair[1]))
		route_mesh.surface_add_vertex(Vector3(local.x, 0.0, local.z))
	route_mesh.surface_end()
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
