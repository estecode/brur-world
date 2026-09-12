extends Node

## Measures runtime frame pacing controls with either a lightweight scene or production main.
##
## Dependencies:
## - DisplayServer exposes the active VSync mode.
## - Engine/OS expose frame-limit and low-processor pacing controls.
## - Production-main mode instantiates the normal main scene and uses the same local runtime data.

const MainScene = preload("res://scenes/main.tscn")
const WARMUP_S := 1.0
const MEASURE_S := 3.0

var _mode := "light"
var _main: Node3D
var _phase_index := 0
var _phase_elapsed := 0.0
var _measuring := false
var _frames := 0
var _sum_delta := 0.0
var _worst_delta := 0.0

var _initial_vsync: DisplayServer.VSyncMode
var _initial_max_fps := 0
var _initial_low_processor := false
var _initial_low_processor_sleep_usec := 0

var _phases: Array[Dictionary] = [
	{"name": "initial"},
	{"name": "vsync_off_unthrottled"},
	{"name": "vsync_off_max60"},
]

func _ready() -> void:
	_mode = OS.get_environment("BRUR_PERF_MODE").strip_edges()
	if _mode.is_empty():
		_mode = "light"
	_initial_vsync = DisplayServer.window_get_vsync_mode()
	_initial_max_fps = Engine.max_fps
	_initial_low_processor = OS.low_processor_usage_mode
	_initial_low_processor_sleep_usec = OS.low_processor_usage_mode_sleep_usec
	print("FRAME_PACING start mode=%s renderer=%s vsync=%d max_fps=%d low_processor=%s low_processor_sleep_usec=%d window=%dx%d" % [
		_mode,
		str(RenderingServer.get_current_rendering_method()),
		int(_initial_vsync),
		_initial_max_fps,
		str(_initial_low_processor),
		_initial_low_processor_sleep_usec,
		get_window().size.x,
		get_window().size.y,
	])
	if _mode == "main":
		if not FileAccess.file_exists("res://world_data/manifest.json"):
			print("FRAME_PACING skipped=no_world_data")
			get_tree().quit(0)
			return
		_main = MainScene.instantiate() as Node3D
		add_child(_main)
	_apply_phase()

func _process(delta: float) -> void:
	_phase_elapsed += delta
	if not _measuring:
		if _phase_elapsed >= WARMUP_S:
			_measuring = true
			_phase_elapsed = 0.0
			_reset_sample()
		return
	_frames += 1
	_sum_delta += delta
	_worst_delta = maxf(_worst_delta, delta)
	if _phase_elapsed < MEASURE_S:
		return
	_emit_result()
	_phase_index += 1
	if _phase_index >= _phases.size():
		_finish()
		return
	_apply_phase()

func _apply_phase() -> void:
	var name := str(_phases[_phase_index]["name"])
	match name:
		"initial":
			DisplayServer.window_set_vsync_mode(_initial_vsync)
			Engine.max_fps = _initial_max_fps
			OS.low_processor_usage_mode = _initial_low_processor
			OS.low_processor_usage_mode_sleep_usec = _initial_low_processor_sleep_usec
		"vsync_off_unthrottled":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0
			OS.low_processor_usage_mode = false
		"vsync_off_max60":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 60
			OS.low_processor_usage_mode = false
	_phase_elapsed = 0.0
	_measuring = false
	_reset_sample()
	print("FRAME_PACING phase_start mode=%s phase=%s vsync=%d max_fps=%d low_processor=%s low_processor_sleep_usec=%d" % [
		_mode,
		name,
		int(DisplayServer.window_get_vsync_mode()),
		Engine.max_fps,
		str(OS.low_processor_usage_mode),
		OS.low_processor_usage_mode_sleep_usec,
	])

func _reset_sample() -> void:
	_frames = 0
	_sum_delta = 0.0
	_worst_delta = 0.0

func _emit_result() -> void:
	var elapsed := maxf(0.000001, _sum_delta)
	var fps := float(_frames) / elapsed
	var avg_ms := elapsed * 1000.0 / float(maxi(1, _frames))
	print("FRAME_PACING mode=%s phase=%s fps=%.2f avg_ms=%.3f worst_ms=%.3f frames=%d vsync=%d max_fps=%d low_processor=%s" % [
		_mode,
		str(_phases[_phase_index]["name"]),
		fps,
		avg_ms,
		_worst_delta * 1000.0,
		_frames,
		int(DisplayServer.window_get_vsync_mode()),
		Engine.max_fps,
		str(OS.low_processor_usage_mode),
	])

func _finish() -> void:
	DisplayServer.window_set_vsync_mode(_initial_vsync)
	Engine.max_fps = _initial_max_fps
	OS.low_processor_usage_mode = _initial_low_processor
	OS.low_processor_usage_mode_sleep_usec = _initial_low_processor_sleep_usec
	print("FRAME_PACING complete mode=%s" % _mode)
	get_tree().quit(0)
