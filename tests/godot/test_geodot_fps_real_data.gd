extends SceneTree

## Measures the GeoDot POC in the same production BRUR Drive composition and
## render-origin crossing pattern used by test_production_fps_real_data.gd.
## Requires the real world_data and BRUR_GEODOT_GPKG.

const GeoDotScene = preload("res://scenes/geodot_poc.tscn")
const SETUP_TIMEOUT_S := 20.0
const SETTLE_TIMEOUT_S := 30.0
const STABLE_S := 0.75
const MEASURE_FRAMES := 360
const CELL_CROSS_INTERVAL := 90
const CELL_BOUNDARY_OFFSET_M := 512.0
const CELL_CROSS_DELTA_M := 2.0
const MAX_AVG_FRAME_MS := 33.4
const MAX_P95_FRAME_MS := 50.0
const MAX_P99_FRAME_MS := 100.0
const MAX_WORST_FRAME_MS := 250.0
const SURFACE_HEIGHT_TOLERANCE_M := 0.001
const SHUTDOWN_SETTLE_FRAMES := 2

var _main: Node3D
var _camera_rig: Node
var _geodot_layer: Node
var _gps_layer: Node
var _player: Node3D
var _setup_elapsed := 0.0
var _settle_elapsed := 0.0
var _stable_elapsed := 0.0
var _state := 0
var _frame_started_usec := 0
var _frame_times: Array[float] = []
var _cell_crossings := 0
var _crossing_start_prepared := false
var _crossing_low_x := 0.0
var _crossing_high_x := 0.0
var _switch_contract_checked := false
var _shutdown_exit_code := -1
var _shutdown_frames := 0

func _initialize() -> void:
	if OS.has_environment("BRUR_PARSE_ONLY"):
		print("GeoDot Drive FPS real-data test parse: OK")
		quit(0)
		return
	var gpkg := OS.get_environment("BRUR_GEODOT_GPKG")
	if gpkg.is_empty() or not FileAccess.file_exists(gpkg):
		_fail("BRUR_GEODOT_GPKG is missing")
		return
	if not FileAccess.file_exists("res://world_data/manifest.json"):
		_fail("missing world_data manifest")
		return
	_main = GeoDotScene.instantiate() as Node3D
	get_root().add_child(_main)
	_camera_rig = _main.get_node_or_null("CameraRig")
	_geodot_layer = _main.get_node_or_null("World/GeoDotWorldLayer")
	_gps_layer = _main.get_node_or_null("GpsRouteLayer")
	if _camera_rig == null or _geodot_layer == null or _gps_layer == null:
		_fail("GeoDot production composition dependencies missing")
		return
	print("GEODOT_DRIVE_FPS_REAL_DATA waiting for production player")

func _process(delta: float) -> bool:
	if _shutdown_exit_code >= 0:
		_shutdown_frames += 1
		if _shutdown_frames >= SHUTDOWN_SETTLE_FRAMES:
			quit(_shutdown_exit_code)
		return false
	if _main == null:
		return false
	match _state:
		0:
			_setup_elapsed += delta
			_player = _gps_layer.call("get_player_vehicle") as Node3D
			if _player != null and bool(_geodot_layer.call("is_ready")):
				if not _verify_renderer_switch_preserves_gameplay_state():
					return false
				if not _verify_shared_surface_height("map"):
					return false
				_camera_rig.call("set_follow_target", _player)
				_camera_rig.call("set_drive_mode", true)
				_state = 1
				print("GEODOT_DRIVE_FPS_REAL_DATA Drive enabled player=", _player.global_position)
			elif _setup_elapsed >= SETUP_TIMEOUT_S:
				_fail("GeoDot/player did not become ready within %.1fs snapshot=%s" % [SETUP_TIMEOUT_S, str(_debug_snapshot())])
		1:
			_settle_elapsed += delta
			if not _verify_shared_surface_height("drive"):
				return false
			var snapshot := _debug_snapshot()
			var active := int(snapshot.get("active_cells", 0))
			var desired := int(snapshot.get("desired_cells", 0))
			var pending := int(snapshot.get("pending_cells", -1))
			if active > 0 and active == desired and pending == 0:
				_stable_elapsed += delta
			else:
				_stable_elapsed = 0.0
			if _stable_elapsed >= STABLE_S:
				if not _crossing_start_prepared:
					_prepare_render_cell_crossing()
				else:
					_begin_measurement()
			elif _settle_elapsed >= SETTLE_TIMEOUT_S:
				_fail("GeoDot world did not settle: snapshot=%s metrics=%s" % [str(snapshot), str(_consume_metrics())])
		2:
			var now_usec := Time.get_ticks_usec()
			if _frame_started_usec > 0:
				_frame_times.append(float(now_usec - _frame_started_usec) / 1000.0)
			if _frame_times.size() >= MEASURE_FRAMES:
				_finish_measurement()
				return false
			if _frame_times.size() > 0 and _frame_times.size() % CELL_CROSS_INTERVAL == 0:
				_cross_render_cell()
			_frame_started_usec = Time.get_ticks_usec()
	return false

func _verify_renderer_switch_preserves_gameplay_state() -> bool:
	if _switch_contract_checked:
		return true
	if not _main.has_method("set_geodot_renderer_enabled") or not _main.has_method("is_geodot_active"):
		_fail("GeoDot POC does not expose in-place renderer switching")
		return false
	var gps_before: Node = _main.get_node_or_null("GpsRouteLayer")
	var camera_before: Node = _main.get_node_or_null("CameraRig")
	var player_before: Node = _gps_layer.call("get_player_vehicle") as Node
	if not bool(_main.call("set_geodot_renderer_enabled", false)) or bool(_main.call("is_geodot_active")):
		_fail("could not switch from GeoDot to legacy presentation in place")
		return false
	if _main.get_node_or_null("GpsRouteLayer") != gps_before or _main.get_node_or_null("CameraRig") != camera_before or _gps_layer.call("get_player_vehicle") != player_before:
		_fail("renderer switch replaced GPS/camera/player gameplay state")
		return false
	if not bool(_main.call("set_geodot_renderer_enabled", true)) or not bool(_main.call("is_geodot_active")):
		_fail("could not switch from legacy back to GeoDot presentation in place")
		return false
	if _main.get_node_or_null("GpsRouteLayer") != gps_before or _main.get_node_or_null("CameraRig") != camera_before or _gps_layer.call("get_player_vehicle") != player_before:
		_fail("renderer switch back to GeoDot replaced GPS/camera/player gameplay state")
		return false
	_switch_contract_checked = true
	print("GEODOT_RENDERER_SWITCH gameplay_state_preserved=true")
	return true

func _verify_shared_surface_height(context: String) -> bool:
	if not _main.has_method("get_road_surface_height"):
		_fail("Main does not expose shared road/building surface height")
		return false
	var expected := float(_main.call("get_road_surface_height"))
	var actual := float((_geodot_layer as Node3D).position.y)
	if absf(actual - expected) > SURFACE_HEIGHT_TOLERANCE_M:
		_fail("GeoDot %s surface y %.6f differs from shared production y %.6f" % [context, actual, expected])
		return false
	return true

func _prepare_render_cell_crossing() -> void:
	var render_origin: Vector3 = _camera_rig.call("get_render_origin_world")
	var boundary_x := render_origin.x + CELL_BOUNDARY_OFFSET_M
	_crossing_low_x = boundary_x - CELL_CROSS_DELTA_M
	_crossing_high_x = boundary_x + CELL_CROSS_DELTA_M
	var prepared := _player.global_position
	prepared.x = _crossing_low_x
	_player.call("set_world_position", prepared)
	if _camera_rig.has_method("_apply_drive_camera"):
		_camera_rig.call("_apply_drive_camera")
	_crossing_start_prepared = true
	_settle_elapsed = 0.0
	_stable_elapsed = 0.0
	print("GEODOT_DRIVE_FPS_REAL_DATA prepared cell boundary low_x=%.1f high_x=%.1f" % [_crossing_low_x, _crossing_high_x])

func _begin_measurement() -> void:
	_state = 2
	_frame_times.clear()
	_frame_started_usec = Time.get_ticks_usec()
	_consume_metrics()
	print("GEODOT_DRIVE_FPS_REAL_DATA measuring snapshot=", _debug_snapshot())

func _cross_render_cell() -> void:
	var before_origin: Vector3 = _camera_rig.call("get_render_origin_world")
	var next_position := _player.global_position
	if absf(next_position.x - _crossing_low_x) <= absf(next_position.x - _crossing_high_x):
		next_position.x = _crossing_high_x
	else:
		next_position.x = _crossing_low_x
	_player.call("set_world_position", next_position)
	if _camera_rig.has_method("_apply_drive_camera"):
		_camera_rig.call("_apply_drive_camera")
	var after_origin: Vector3 = _camera_rig.call("get_render_origin_world")
	if is_equal_approx(after_origin.x, before_origin.x):
		_fail("render-cell crossing did not change render origin")
		return
	_cell_crossings += 1

func _finish_measurement() -> void:
	_frame_times.sort()
	var sum_ms := 0.0
	for value in _frame_times:
		sum_ms += value
	var count := _frame_times.size()
	var avg_ms := sum_ms / float(maxi(1, count))
	var p95_ms := _percentile(0.95)
	var p99_ms := _percentile(0.99)
	var worst_ms := _frame_times[count - 1]
	var fps := 1000.0 / maxf(0.001, avg_ms)
	var metrics := _consume_metrics()
	var snapshot := _debug_snapshot()
	print("GEODOT_DRIVE_FPS_REAL_DATA fps=%.2f avg_ms=%.3f p95_ms=%.3f p99_ms=%.3f worst_ms=%.3f frames=%d cell_crossings=%d snapshot=%s metrics=%s" % [fps, avg_ms, p95_ms, p99_ms, worst_ms, count, _cell_crossings, str(snapshot), str(metrics)])
	if avg_ms > MAX_AVG_FRAME_MS:
		_fail("average %.3f ms exceeds %.1f ms" % [avg_ms, MAX_AVG_FRAME_MS])
		return
	if p95_ms > MAX_P95_FRAME_MS:
		_fail("p95 %.3f ms exceeds %.1f ms" % [p95_ms, MAX_P95_FRAME_MS])
		return
	if p99_ms > MAX_P99_FRAME_MS:
		_fail("p99 %.3f ms exceeds %.1f ms" % [p99_ms, MAX_P99_FRAME_MS])
		return
	if worst_ms > MAX_WORST_FRAME_MS:
		_fail("worst frame %.3f ms exceeds %.1f ms" % [worst_ms, MAX_WORST_FRAME_MS])
		return
	if _cell_crossings < 3:
		_fail("measurement did not exercise enough render-cell crossings")
		return
	if int(snapshot.get("active_cells", 0)) > int(snapshot.get("max_resident_cells", 0)):
		_fail("resident-cell bound exceeded")
		return
	if int(snapshot.get("pending_cells", 0)) > int(snapshot.get("max_pending_cells", 0)) + 1:
		_fail("pending-cell bound exceeded")
		return
	print("GeoDot Drive FPS real-data test: OK")
	_shutdown_and_quit(0)

func _percentile(fraction: float) -> float:
	var index := clampi(int(ceil(float(_frame_times.size()) * fraction)) - 1, 0, _frame_times.size() - 1)
	return _frame_times[index]

func _debug_snapshot() -> Dictionary:
	if _main != null and _main.has_method("geodot_debug_snapshot"):
		return _main.call("geodot_debug_snapshot")
	return {}

func _consume_metrics() -> Dictionary:
	if _geodot_layer != null and _geodot_layer.has_method("consume_perf_metrics"):
		return _geodot_layer.call("consume_perf_metrics")
	return {}

func _shutdown_and_quit(exit_code: int) -> void:
	if _shutdown_exit_code >= 0:
		return
	if _geodot_layer != null and _geodot_layer.has_method("shutdown"):
		_geodot_layer.call("shutdown")
	_geodot_layer = null
	_gps_layer = null
	_camera_rig = null
	_player = null
	if _main != null:
		# This test owns the production scene outright. A deferred queue_free() leaves
		# renderer RIDs alive until the SceneTree delete queue is flushed, which can
		# overlap Godot 4.7/macOS renderer teardown after this headless child exits.
		# Free synchronously while RenderingServer and the GeoDot extension are alive.
		_main.free()
	_main = null
	_shutdown_exit_code = exit_code
	_shutdown_frames = 0

func _fail(message: String) -> void:
	push_error("GeoDot Drive FPS real-data test failed: " + message)
	_shutdown_and_quit(1)
