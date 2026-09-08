extends CanvasLayer

# On-screen runtime/performance readout with a persistent one-second metrics log.
#
# Dependencies:
# - Reads one-second metrics from Main and GpsRouteLayer.
# - Writes presentation/debug data only; it owns no routing or world behavior.

const PERF_LOG_PATH: String = "user://brur_performance.log"
const LUND_FOCUS: Vector3 = Vector3(-489086.0, 0.0, 1582123.0)
const LUND_DISTANCE: float = 12472.0

@onready var main: Node = get_parent()
@onready var camera_rig: Node = main.get_node("CameraRig")
@onready var camera: Camera3D = camera_rig.get_node("Camera3D") as Camera3D
@onready var label: Label = $Panel/Label

var sample_time: float = 0.0
var frame_count: int = 0
var frame_sum_ms: float = 0.0
var worst_frame_ms: float = 0.0
var shown_avg_ms: float = 0.0
var shown_worst_ms: float = 0.0
var perf_log: FileAccess = null
var build_id: String = "unknown"
var shown_road_build_ms: float = 0.0
var shown_road_build_max_ms: float = 0.0
var shown_road_tiles_built: int = 0
var shown_road_pending: int = 0
var shown_road_refresh_ms: float = 0.0
var shown_cache_hits: int = 0
var shown_cache_misses: int = 0
var shown_gps_queries: int = 0
var shown_gps_route_ms: float = 0.0
var shown_gps_route_max_ms: float = 0.0
var shown_gps_settled: int = 0
var shown_gps_relaxed: int = 0
var shown_gps_parse_ms: float = 0.0
var shown_gps_apply_ms: float = 0.0
var shown_gps_points: int = 0
var shown_gps_failures: int = 0
var shown_gps_failure_reason: String = ""
var shown_gps_failed_leg: int = -1
var shown_gps_busy: bool = false

func _ready() -> void:
	build_id = _read_build_id()
	_open_perf_log()
	_create_lund_button()

func _read_build_id() -> String:
	var output: Array = []
	var exit_code: int = OS.execute("git", PackedStringArray(["rev-parse", "--short", "HEAD"]), output, true)
	if exit_code == 0 and not output.is_empty():
		var value: String = str(output[0]).strip_edges()
		if not value.is_empty():
			return value
	return "unknown"

func _create_lund_button() -> void:
	var button: Button = Button.new()
	button.text = "Lund"
	button.tooltip_text = "Focus Lund at the saved gameplay zoom"
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.position = Vector2(-124.0, 14.0)
	button.custom_minimum_size = Vector2(110.0, 34.0)
	button.pressed.connect(_focus_lund)
	add_child(button)

func _focus_lund() -> void:
	camera_rig.call("set_view", LUND_FOCUS, LUND_DISTANCE)

func _open_perf_log() -> void:
	if FileAccess.file_exists(PERF_LOG_PATH):
		perf_log = FileAccess.open(PERF_LOG_PATH, FileAccess.READ_WRITE)
		if perf_log != null:
			perf_log.seek_end()
	else:
		perf_log = FileAccess.open(PERF_LOG_PATH, FileAccess.WRITE)
	if perf_log == null:
		push_warning("Could not open performance log: " + PERF_LOG_PATH)
		return
	perf_log.store_line("")
	perf_log.store_line("=== BRUR PERFORMANCE SESSION %s | build=%s ===" % [Time.get_datetime_string_from_system(), build_id])
	perf_log.store_line("time,build,fps,avg_frame_ms,worst_1s_ms,distance_m,lod,road_tiles,road_cache,pois,poi_tile_cache,draw_calls,objects,nodes,camera_near,camera_far,fov,road_build_ms,road_build_max_ms,road_tiles_built,road_pending,road_refresh_ms,cache_hits,cache_misses,gps_queries,gps_route_ms,gps_route_max_ms,gps_settled,gps_relaxed,gps_parse_ms,gps_apply_ms,gps_points,gps_failures,gps_failure_reason,gps_failed_leg,gps_busy")
	perf_log.flush()
	print("Performance log: ", ProjectSettings.globalize_path(PERF_LOG_PATH), " | build: ", build_id)

func _process(delta: float) -> void:
	var frame_ms: float = delta * 1000.0
	frame_count += 1
	frame_sum_ms += frame_ms
	worst_frame_ms = maxf(worst_frame_ms, frame_ms)
	sample_time += delta
	var write_sample: bool = false
	if sample_time >= 1.0:
		shown_avg_ms = frame_sum_ms / float(maxi(1, frame_count))
		shown_worst_ms = worst_frame_ms
		sample_time = 0.0
		frame_count = 0
		frame_sum_ms = 0.0
		worst_frame_ms = 0.0
		write_sample = true
		if main.has_method("consume_perf_metrics"):
			var road_metrics: Dictionary = main.call("consume_perf_metrics") as Dictionary
			shown_road_build_ms = float(road_metrics.get("road_build_ms", 0.0))
			shown_road_build_max_ms = float(road_metrics.get("road_build_max_ms", 0.0))
			shown_road_tiles_built = int(road_metrics.get("road_tiles_built", 0))
			shown_road_pending = int(road_metrics.get("road_pending", 0))
			shown_road_refresh_ms = float(road_metrics.get("road_refresh_ms", 0.0))
			shown_cache_hits = int(road_metrics.get("road_cache_hits", 0))
			shown_cache_misses = int(road_metrics.get("road_cache_misses", 0))
		var gps_layer: Node = main.get_node_or_null("GpsRouteLayer")
		if gps_layer != null and gps_layer.has_method("consume_perf_metrics"):
			var gps_metrics: Dictionary = gps_layer.call("consume_perf_metrics") as Dictionary
			shown_gps_queries = int(gps_metrics.get("gps_queries", 0))
			shown_gps_route_ms = float(gps_metrics.get("gps_route_ms", 0.0))
			shown_gps_route_max_ms = float(gps_metrics.get("gps_route_max_ms", 0.0))
			shown_gps_settled = int(gps_metrics.get("gps_settled", 0))
			shown_gps_relaxed = int(gps_metrics.get("gps_relaxed", 0))
			shown_gps_parse_ms = float(gps_metrics.get("gps_parse_ms", 0.0))
			shown_gps_apply_ms = float(gps_metrics.get("gps_apply_ms", 0.0))
			shown_gps_points = int(gps_metrics.get("gps_points", 0))
			shown_gps_failures = int(gps_metrics.get("gps_failures", 0))
			shown_gps_failure_reason = str(gps_metrics.get("gps_failure_reason", ""))
			shown_gps_failed_leg = int(gps_metrics.get("gps_failed_leg", -1))
			shown_gps_busy = bool(gps_metrics.get("gps_busy", false))

	var distance: float = float(camera_rig.call("get_distance"))
	var focus: Vector3 = camera_rig.call("get_focus_world") as Vector3
	var lod: int = int(main.get("current_lod"))
	var loaded_value: Variant = main.get("loaded")
	var loaded_count: int = 0
	if typeof(loaded_value) == TYPE_DICTIONARY:
		loaded_count = (loaded_value as Dictionary).size()
	var cache_value: Variant = main.get("mesh_cache")
	var mesh_cache_count: int = 0
	if typeof(cache_value) == TYPE_DICTIONARY:
		mesh_cache_count = (cache_value as Dictionary).size()
	var min_tile: Vector2i = main.get("last_min_tile") as Vector2i
	var max_tile: Vector2i = main.get("last_max_tile") as Vector2i
	var spacing: float = float(main.get("current_layer_spacing"))
	var ground_hits: PackedVector3Array = camera_rig.call("get_ground_view_corners") as PackedVector3Array

	var poi_count: int = 0
	var poi_cache_count: int = 0
	var poi_layer: Node = main.get_node_or_null("PoiLayer")
	if poi_layer != null:
		var pois_value: Variant = poi_layer.get("active_pois")
		if typeof(pois_value) == TYPE_ARRAY:
			poi_count = (pois_value as Array).size()
		var poi_cache_value: Variant = poi_layer.get("tile_cache")
		if typeof(poi_cache_value) == TYPE_DICTIONARY:
			poi_cache_count = (poi_cache_value as Dictionary).size()

	var fps: float = Engine.get_frames_per_second()
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

	if write_sample:
		_write_perf_sample(fps, distance, lod, loaded_count, mesh_cache_count, poi_count, poi_cache_count, draw_calls, objects, nodes)

	var failure_text: String = ""
	if shown_gps_failures > 0:
		failure_text = "   failures %d leg %d %s" % [shown_gps_failures, shown_gps_failed_leg + 1, shown_gps_failure_reason]
	label.text = (
		"BRUR WORLD DEBUG   build: %s\n" % build_id
		+ "FPS: %.0f   frame avg: %.2f ms   worst 1s: %.2f ms\n" % [fps, shown_avg_ms, shown_worst_ms]
		+ "draw calls: %d   objects: %d   nodes: %d\n" % [draw_calls, objects, nodes]
		+ "distance: %.0f m   lod: %d   road tiles: %d   road cache: %d\n" % [distance, lod, loaded_count, mesh_cache_count]
		+ "road build: %.1f ms total / %.1f ms max   built: %d   pending: %d\n" % [shown_road_build_ms, shown_road_build_max_ms, shown_road_tiles_built, shown_road_pending]
		+ "road refresh: %.1f ms   cache hit/miss: %d/%d\n" % [shown_road_refresh_ms, shown_cache_hits, shown_cache_misses]
		+ "GPS: q %d route %.1f/%.1f ms parse %.1f apply %.1f points %d busy %s%s\n" % [shown_gps_queries, shown_gps_route_ms, shown_gps_route_max_ms, shown_gps_parse_ms, shown_gps_apply_ms, shown_gps_points, str(shown_gps_busy), failure_text]
		+ "GPS search: settled %d   relaxed %d\n" % [shown_gps_settled, shown_gps_relaxed]
		+ "POIs: %d   POI tile cache: %d\n" % [poi_count, poi_cache_count]
		+ "camera near/far: %.1f / %.0f   fov: %.1f\n" % [camera.near, camera.far, camera.fov]
		+ "focus: x %.0f   z %.0f\n" % [focus.x, focus.z]
		+ "visible tiles: %s -> %s\n" % [str(min_tile), str(max_tile)]
		+ "ground corner hits: %d / 4   layer spacing: %.1f m\n" % [ground_hits.size(), spacing]
		+ "perf log: user://brur_performance.log"
	)

func _csv_safe(value: String) -> String:
	return value.replace(",", ";").replace("\n", " ").replace("\r", " ")

func _write_perf_sample(
	fps: float,
	distance: float,
	lod: int,
	road_tiles: int,
	road_cache: int,
	poi_count: int,
	poi_cache: int,
	draw_calls: int,
	objects: int,
	nodes: int
) -> void:
	if perf_log == null:
		return
	var line: String = "%s,%s,%.0f,%.3f,%.3f,%.0f,%d,%d,%d,%d,%d,%d,%d,%d,%.2f,%.0f,%.2f,%.3f,%.3f,%d,%d,%.3f,%d,%d,%d,%.3f,%.3f,%d,%d,%.3f,%.3f,%d,%d,%s,%d,%s" % [
		Time.get_datetime_string_from_system(), build_id, fps, shown_avg_ms, shown_worst_ms, distance, lod,
		road_tiles, road_cache, poi_count, poi_cache, draw_calls, objects, nodes,
		camera.near, camera.far, camera.fov,
		shown_road_build_ms, shown_road_build_max_ms, shown_road_tiles_built, shown_road_pending,
		shown_road_refresh_ms, shown_cache_hits, shown_cache_misses,
		shown_gps_queries, shown_gps_route_ms, shown_gps_route_max_ms, shown_gps_settled, shown_gps_relaxed,
		shown_gps_parse_ms, shown_gps_apply_ms, shown_gps_points, shown_gps_failures,
		_csv_safe(shown_gps_failure_reason), shown_gps_failed_leg, str(shown_gps_busy),
	]
	perf_log.store_line(line)
	if shown_worst_ms >= 33.3:
		perf_log.store_line("PERF SPIKE,%s,build=%s,worst_frame_ms=%.3f,distance=%.0f,lod=%d,pois=%d,road_tiles=%d,road_build_max_ms=%.3f,road_pending=%d,gps_queries=%d,gps_route_max_ms=%.3f,gps_parse_ms=%.3f,gps_apply_ms=%.3f,gps_points=%d,gps_failures=%d,gps_failure_reason=%s,gps_failed_leg=%d,gps_busy=%s" % [
			Time.get_datetime_string_from_system(), build_id, shown_worst_ms, distance, lod, poi_count, road_tiles, shown_road_build_max_ms, shown_road_pending,
			shown_gps_queries, shown_gps_route_max_ms, shown_gps_parse_ms, shown_gps_apply_ms, shown_gps_points,
			shown_gps_failures, _csv_safe(shown_gps_failure_reason), shown_gps_failed_leg, str(shown_gps_busy)
		])
	perf_log.flush()
