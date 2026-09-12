extends Node

## Runs objective production-renderer FPS variants and exits without human judgment.
##
## Dependencies:
## - Instantiates the production main scene with the exact local runtime world_data.
## - Uses only composition-owned scene nodes for visibility/process toggles; no alternate renderer or world truth.

const MainScene = preload("res://scenes/main.tscn")
const SETTLE_TIMEOUT_S := 50.0
const SETTLE_STABLE_S := 1.0
const WARMUP_S := 1.25
const MEASURE_S := 4.0

var _main: Node3D
var _clouds: Node
var _world: Node3D
var _city_lights: Node3D
var _phase_index := -1
var _phase_elapsed := 0.0
var _settle_elapsed := 0.0
var _settle_stable := 0.0
var _measuring := false
var _frame_count := 0
var _sum_delta := 0.0
var _worst_delta := 0.0
var _draw_call_sum := 0.0
var _initial_window_size := Vector2i.ZERO
var _phases: Array[Dictionary] = [
	{"name": "baseline", "world": true, "clouds": true, "city": true, "main3d": true, "size": Vector2i.ZERO},
	{"name": "clouds_off", "world": true, "clouds": false, "city": true, "main3d": true, "size": Vector2i.ZERO},
	{"name": "world_off", "world": false, "clouds": true, "city": true, "main3d": true, "size": Vector2i.ZERO},
	{"name": "world_cloud_city_off", "world": false, "clouds": false, "city": false, "main3d": true, "size": Vector2i.ZERO},
	{"name": "main_3d_off", "world": false, "clouds": false, "city": false, "main3d": false, "size": Vector2i.ZERO},
	{"name": "baseline_960x540", "world": true, "clouds": true, "city": true, "main3d": true, "size": Vector2i(960, 540)},
]

func _ready() -> void:
	if not FileAccess.file_exists("res://world_data/manifest.json"):
		print("PERF_RENDER_DIAG skipped=no_world_data")
		get_tree().quit(0)
		return
	_initial_window_size = get_window().size
	print("PERF_RENDER_DIAG start renderer=%s window=%dx%d" % [
		str(RenderingServer.get_current_rendering_method()),
		_initial_window_size.x,
		_initial_window_size.y,
	])
	_main = MainScene.instantiate() as Node3D
	add_child(_main)
	_world = _main.get_node_or_null("World") as Node3D
	_clouds = _main.get_node_or_null("CloudField")
	_city_lights = _main.get_node_or_null("CityLights") as Node3D
	if _world == null or _clouds == null:
		push_error("PERF_RENDER_DIAG missing production world/cloud composition")
		get_tree().quit(1)
		return
	print("PERF_RENDER_DIAG settling roads before timed phases")

func _process(delta: float) -> void:
	if _main == null:
		return
	if _phase_index < 0:
		_process_settle(delta)
		return
	_process_phase(delta)

func _process_settle(delta: float) -> void:
	_settle_elapsed += delta
	var pending := _road_pending()
	if pending == 0:
		_settle_stable += delta
	else:
		_settle_stable = 0.0
	if _settle_stable >= SETTLE_STABLE_S or _settle_elapsed >= SETTLE_TIMEOUT_S:
		print("PERF_RENDER_DIAG settled elapsed_s=%.2f road_tiles=%d road_pending=%d timeout=%s" % [
			_settle_elapsed,
			_road_tiles(),
			pending,
			str(_settle_elapsed >= SETTLE_TIMEOUT_S),
		])
		_phase_index = 0
		_apply_phase()

func _process_phase(delta: float) -> void:
	_phase_elapsed += delta
	if not _measuring:
		if _phase_elapsed >= WARMUP_S:
			_measuring = true
			_phase_elapsed = 0.0
			_reset_sample()
		return

	_frame_count += 1
	_sum_delta += delta
	_worst_delta = maxf(_worst_delta, delta)
	_draw_call_sum += float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	if _phase_elapsed < MEASURE_S:
		return
	_emit_phase_result()
	_phase_index += 1
	if _phase_index >= _phases.size():
		_finish()
		return
	_apply_phase()

func _apply_phase() -> void:
	var phase: Dictionary = _phases[_phase_index]
	_main.visible = bool(phase["main3d"])
	_world.visible = bool(phase["world"])
	_clouds.visible = bool(phase["clouds"])
	_clouds.set_process(bool(phase["clouds"]))
	if _city_lights != null:
		_city_lights.visible = bool(phase["city"])
	var requested_size: Vector2i = phase["size"] as Vector2i
	get_window().size = _initial_window_size if requested_size == Vector2i.ZERO else requested_size
	_phase_elapsed = 0.0
	_measuring = false
	_reset_sample()
	print("PERF_RENDER_DIAG phase_start=%s window=%dx%d" % [
		str(phase["name"]), get_window().size.x, get_window().size.y
	])

func _reset_sample() -> void:
	_frame_count = 0
	_sum_delta = 0.0
	_worst_delta = 0.0
	_draw_call_sum = 0.0

func _emit_phase_result() -> void:
	var phase: Dictionary = _phases[_phase_index]
	var elapsed := maxf(0.000001, _sum_delta)
	var fps := float(_frame_count) / elapsed
	var avg_ms := elapsed * 1000.0 / float(maxi(1, _frame_count))
	var worst_ms := _worst_delta * 1000.0
	var draw_calls := _draw_call_sum / float(maxi(1, _frame_count))
	print("PERF_RENDER_DIAG phase=%s fps=%.2f avg_ms=%.3f worst_ms=%.3f draw_calls=%.1f frames=%d road_tiles=%d road_pending=%d window=%dx%d" % [
		str(phase["name"]), fps, avg_ms, worst_ms, draw_calls, _frame_count,
		_road_tiles(), _road_pending(), get_window().size.x, get_window().size.y,
	])

func _road_tiles() -> int:
	var loaded: Variant = _main.get("loaded")
	return (loaded as Dictionary).size() if typeof(loaded) == TYPE_DICTIONARY else -1

func _road_pending() -> int:
	var pending: Variant = _main.get("pending_tiles")
	return (pending as Array).size() if typeof(pending) == TYPE_ARRAY else -1

func _finish() -> void:
	get_window().size = _initial_window_size
	print("PERF_RENDER_DIAG complete renderer=%s" % str(RenderingServer.get_current_rendering_method()))
	get_tree().quit(0)
