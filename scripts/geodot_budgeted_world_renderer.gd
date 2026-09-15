extends "res://scripts/geodot_world_renderer.gd"
class_name GeoDotBudgetedWorldRenderer

@export var streaming_budget_ms := 3.0
@export var max_publishes_per_frame := 1
var _last_publish_frame_ms := 0.0
var _over_budget_publishes := 0

func set_enabled(value: bool) -> void:
	# Streaming activity and residency are deliberately separate. A temporary LOD
	# demotion must not destroy completed geometry: rapid reverse zoom should reuse
	# the warm representation instead of rebuilding it from the GeoPackage.
	_enabled = value and _ready
	set_process(_enabled)
	if not _enabled:
		_generation += 1
		_queue.clear()
		_queued.clear()
		_ready_results.clear()
		_desired.clear()
		_shutdown_query_workers()
		_apply_presentation_visibility()
		return
	_refresh_desired(true)
	_apply_presentation_visibility()

func set_presentation_visible(value: bool) -> void:
	_presentation_visible = value
	_apply_presentation_visibility()

func _apply_presentation_visibility() -> void:
	for key_value in _active.keys():
		var key := String(key_value)
		var entry: Dictionary = _active[key]
		var node := entry.get("node") as Node3D
		if node == null:
			continue
		var owns_desired := _desired.has(key) and int(entry.get("lod", -1)) == int(_desired[key])
		node.visible = _presentation_visible and _enabled and owns_desired

func _publish_cell(request: Dictionary, result: Dictionary) -> void:
	super._publish_cell(request, result)
	_apply_presentation_visibility()

func _refresh_desired(force: bool) -> void:
	super._refresh_desired(force)
	_apply_presentation_visibility()

func ready_desired_cells() -> int:
	var count := 0
	for key_value in _desired.keys():
		var key := String(key_value)
		if _active.has(key) and int((_active[key] as Dictionary).get("lod", -1)) == int(_desired[key]):
			count += 1
	return count

func _process(delta: float) -> void:
	if not _enabled: return
	_poll_queries()
	var started := Time.get_ticks_usec()
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
	snapshot["presentation_visible"] = _presentation_visible
	snapshot["ready_desired_cells"] = ready_desired_cells()
	snapshot["warm_resident_cells"] = _active.size()
	return snapshot
