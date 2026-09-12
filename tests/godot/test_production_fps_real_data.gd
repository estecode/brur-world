extends SceneTree

## Measures the production main scene with local runtime data and exits automatically.
## Dependencies: production main scene and the real world_data linked by local PR check.

const MainScene = preload("res://scenes/main.tscn")
const SETTLE_TIMEOUT_S := 15.0
const STABLE_S := 0.5
const MEASURE_S := 3.0
const MAX_AVG_FRAME_MS := 33.4

var _main: Node3D
var _settle_elapsed := 0.0
var _stable_elapsed := 0.0
var _measuring := false
var _measure_elapsed := 0.0
var _frame_count := 0
var _sum_delta := 0.0
var _worst_delta := 0.0

func _initialize() -> void:
	if not FileAccess.file_exists("res://world_data/manifest.json"):
		push_error("production FPS real-data test failed: missing world_data manifest")
		quit(1)
		return
	_main = MainScene.instantiate() as Node3D
	get_root().add_child(_main)
	print("PRODUCTION_FPS_REAL_DATA settling")

func _process(delta: float) -> bool:
	if _main == null:
		return true
	if not _measuring:
		_settle_elapsed += delta
		var pending := _road_pending()
		if pending == 0:
			_stable_elapsed += delta
		else:
			_stable_elapsed = 0.0
		if _stable_elapsed >= STABLE_S or _settle_elapsed >= SETTLE_TIMEOUT_S:
			print("PRODUCTION_FPS_REAL_DATA settled elapsed_s=%.2f road_pending=%d" % [_settle_elapsed, pending])
			_measuring = true
		return true
	_measure_elapsed += delta
	_frame_count += 1
	_sum_delta += delta
	_worst_delta = maxf(_worst_delta, delta)
	if _measure_elapsed < MEASURE_S:
		return true
	var avg_ms := _sum_delta * 1000.0 / float(maxi(1, _frame_count))
	var fps := float(_frame_count) / maxf(0.000001, _sum_delta)
	print("PRODUCTION_FPS_REAL_DATA fps=%.2f avg_ms=%.3f worst_ms=%.3f frames=%d road_pending=%d" % [fps, avg_ms, _worst_delta * 1000.0, _frame_count, _road_pending()])
	if avg_ms > MAX_AVG_FRAME_MS:
		push_error("production FPS real-data test failed: average %.3f ms exceeds %.1f ms" % [avg_ms, MAX_AVG_FRAME_MS])
		quit(1)
	else:
		print("production FPS real-data test: OK")
		quit(0)
	return true

func _road_pending() -> int:
	var pending: Variant = _main.get("pending_tiles")
	return (pending as Array).size() if typeof(pending) == TYPE_ARRAY else -1
