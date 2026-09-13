extends SceneTree

## Measures production Drive frame pacing with real local world data, buildings enabled, and render-cell crossings.
##
## Dependencies:
## - Uses the production main scene, GPS/player composition, CameraRig, BuildingStreamLayer, and Drive render-origin adapter.
## - Requires the real world_data linked/prepared by the local PR check; owns no alternate world implementation.

const MainScene = preload("res://scenes/main.tscn")
const SETUP_TIMEOUT_S := 15.0
const SETTLE_TIMEOUT_S := 20.0
const STABLE_S := 0.75
const MEASURE_FRAMES := 360
const CELL_CROSS_INTERVAL := 90
const MAX_AVG_FRAME_MS := 33.4
const MAX_P95_FRAME_MS := 50.0
const MAX_WORST_FRAME_MS := 250.0

var _main: Node3D
var _camera_rig: Node
var _building_layer: Node
var _gps_layer: Node
var _player: Node3D
var _setup_elapsed := 0.0
var _settle_elapsed := 0.0
var _stable_elapsed := 0.0
var _state := 0
var _measure_started_usec := 0
var _frame_started_usec := 0
var _frame_times: Array[float] = []
var _cell_crossings := 0

func _initialize() -> void:
	# Hosted CI has no full Sweden runtime dataset. This mode still compiles the
	# complete script and its production scene dependencies so local-only test
	# changes cannot silently ship with a parse error.
	if OS.has_environment("BRUR_PARSE_ONLY"):
		print("production Drive FPS real-data test parse: OK")
		quit(0)
		return
	if not FileAccess.file_exists("res://world_data/manifest.json"):
		push_error("production Drive FPS real-data test failed: missing world_data manifest")
		quit(1)
		return
	if not FileAccess.file_exists("res://world_data/background.brmap"):
		push_error("production Drive FPS real-data test failed: missing background.brmap")
		quit(1)
		return
	_main = MainScene.instantiate() as Node3D
	get_root().add_child(_main)
	_camera_rig = _main.get_node_or_null("CameraRig")
	_building_layer = _main.get_node_or_null("BuildingLayer")
	_gps_layer = _main.get_node_or_null("GpsRouteLayer")
	if _camera_rig == null or _building_layer == null or _gps_layer == null:
		push_error("production Drive FPS real-data test failed: production scene dependencies missing")
		quit(1)
		return
	# HUS is intentionally off by default in gameplay. This performance regression
	# specifically concerns Drive with buildings visible, so enable the production
	# stream explicitly instead of accidentally benchmarking the cheap default.
	_building_layer.call("set_streaming_enabled", true)
	print("PRODUCTION_DRIVE_FPS_REAL_DATA waiting for production player")

func _process(delta: float) -> bool:
	# SceneTree/MainLoop uses true as a request to terminate. Keep returning false
	# until _finish_measurement() or _fail() explicitly calls quit().
	if _main == null:
		return false
	match _state:
		0:
			_setup_elapsed += delta
			_player = _gps_layer.call("get_player_vehicle") as Node3D
			if _player != null:
				_camera_rig.call("set_follow_target", _player)
				_camera_rig.call("set_drive_mode", true)
				_state = 1
				print("PRODUCTION_DRIVE_FPS_REAL_DATA Drive enabled player=", _player.global_position)
			elif _setup_elapsed >= SETUP_TIMEOUT_S:
				_fail("production player did not become ready within %.1fs" % SETUP_TIMEOUT_S)
		1:
			_settle_elapsed += delta
			var road_pending := _road_pending()
			var buildings_ready := bool(_building_layer.call("is_viewport_ready"))
			if road_pending == 0 and buildings_ready:
				_stable_elapsed += delta
			else:
				_stable_elapsed = 0.0
			if _stable_elapsed >= STABLE_S:
				_begin_measurement()
			elif _settle_elapsed >= SETTLE_TIMEOUT_S:
				_fail("production Drive did not settle: road_pending=%d buildings_ready=%s" % [road_pending, str(buildings_ready)])
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

func _begin_measurement() -> void:
	_state = 2
	_measure_started_usec = Time.get_ticks_usec()
	_frame_started_usec = _measure_started_usec
	_frame_times.clear()
	print("PRODUCTION_DRIVE_FPS_REAL_DATA measuring road_pending=%d buildings_ready=%s active_chunks=%d" % [
		_road_pending(),
		str(_building_layer.call("is_viewport_ready")),
		_active_building_chunks(),
	])

func _cross_render_cell() -> void:
	# Use the production player API so CameraRig, building streaming, road streaming,
	# and floating-origin composition observe the same logical movement contract as gameplay.
	var next_position := _player.global_position + Vector3(1100.0, 0.0, 0.0)
	_player.call("set_world_position", next_position)
	if _camera_rig.has_method("_apply_drive_camera"):
		_camera_rig.call("_apply_drive_camera")
	_cell_crossings += 1

func _finish_measurement() -> void:
	_frame_times.sort()
	var sum_ms := 0.0
	for value in _frame_times:
		sum_ms += value
	var avg_ms := sum_ms / float(maxi(1, _frame_times.size()))
	var p95_index := clampi(int(ceil(float(_frame_times.size()) * 0.95)) - 1, 0, _frame_times.size() - 1)
	var p95_ms := _frame_times[p95_index]
	var worst_ms := _frame_times[_frame_times.size() - 1]
	var fps := 1000.0 / maxf(0.001, avg_ms)
	print("PRODUCTION_DRIVE_FPS_REAL_DATA fps=%.2f avg_ms=%.3f p95_ms=%.3f worst_ms=%.3f frames=%d cell_crossings=%d road_pending=%d buildings_ready=%s active_chunks=%d" % [
		fps, avg_ms, p95_ms, worst_ms, _frame_times.size(), _cell_crossings,
		_road_pending(), str(_building_layer.call("is_viewport_ready")), _active_building_chunks(),
	])
	if avg_ms > MAX_AVG_FRAME_MS:
		_fail("average %.3f ms exceeds %.1f ms" % [avg_ms, MAX_AVG_FRAME_MS])
		return
	if p95_ms > MAX_P95_FRAME_MS:
		_fail("p95 %.3f ms exceeds %.1f ms" % [p95_ms, MAX_P95_FRAME_MS])
		return
	if worst_ms > MAX_WORST_FRAME_MS:
		_fail("worst frame %.3f ms exceeds %.1f ms (2 FPS class hitch regression)" % [worst_ms, MAX_WORST_FRAME_MS])
		return
	if _cell_crossings < 3:
		_fail("measurement did not exercise enough render-cell crossings")
		return
	if not bool(_building_layer.call("is_viewport_ready")):
		_fail("building viewport was not ready after Drive measurement")
		return
	print("production Drive FPS real-data test: OK")
	quit(0)

func _road_pending() -> int:
	var pending: Variant = _main.get("pending_tiles")
	return (pending as Array).size() if typeof(pending) == TYPE_ARRAY else -1

func _active_building_chunks() -> int:
	var value: Variant = _building_layer.get("_active_chunks")
	return int(value) if value != null else -1

func _fail(message: String) -> void:
	push_error("production Drive FPS real-data test failed: " + message)
	quit(1)
