extends "res://scripts/geodot_world_renderer.gd"
class_name GeoDotBudgetedWorldRenderer

@export var streaming_budget_ms := 3.0
@export var max_publishes_per_frame := 1
var _last_publish_frame_ms := 0.0
var _over_budget_publishes := 0

func _process(delta: float) -> void:
	if not _enabled: return
	_poll_queries()
	var started := Time.get_ticks_usec()
	# Mesh publication itself is currently atomic in Godot. Never compound an
	# expensive publication with another one in the same frame; query work stays
	# on workers and later results remain queued for subsequent frames.
	if not _ready_results.is_empty():
		_publish_one_ready_result()
		_last_publish_frame_ms = float(Time.get_ticks_usec()-started)/1000.0
		if _last_publish_frame_ms > maxf(0.25,streaming_budget_ms): _over_budget_publishes += 1
	_refresh_accum += delta
	if _refresh_accum >= refresh_interval_s:
		_refresh_accum=0.0; _refresh_desired(false)
	_start_queries_if_needed()

func debug_snapshot() -> Dictionary:
	var snapshot := super.debug_snapshot()
	snapshot["streaming_budget_ms"] = streaming_budget_ms
	snapshot["last_publish_frame_ms"] = _last_publish_frame_ms
	snapshot["over_budget_publishes"] = _over_budget_publishes
	return snapshot
