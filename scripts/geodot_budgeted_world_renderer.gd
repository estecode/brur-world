extends "res://scripts/geodot_world_renderer.gd"
class_name GeoDotBudgetedWorldRenderer

@export var streaming_budget_ms := 3.0
@export var max_publishes_per_frame := 4

func _process(delta: float) -> void:
	if not _enabled: return
	_poll_queries()
	var started := Time.get_ticks_usec(); var publishes := 0
	while not _ready_results.is_empty() and publishes < maxi(1,max_publishes_per_frame):
		if publishes > 0 and float(Time.get_ticks_usec()-started)/1000.0 >= maxf(0.25,streaming_budget_ms): break
		_publish_one_ready_result(); publishes += 1
	_refresh_accum += delta
	if _refresh_accum >= refresh_interval_s:
		_refresh_accum=0.0; _refresh_desired(false)
	_start_queries_if_needed()
