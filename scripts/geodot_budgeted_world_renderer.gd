extends "res://scripts/geodot_world_renderer.gd"
class_name GeoDotBudgetedWorldRenderer

@export var streaming_budget_ms := 3.0
@export var max_publishes_per_frame := 1
var _last_publish_frame_ms := 0.0
var _over_budget_publishes := 0
var _resident_tick := 0

func set_enabled(value: bool) -> void:
	_enabled = value and _ready; set_process(_enabled)
	if not _enabled:
		_streaming_enabled = false; _generation += 1; _queue.clear(); _queued.clear(); _ready_results.clear(); _desired.clear(); _shutdown_query_workers(); _apply_presentation_visibility(); return
	_streaming_enabled = true; _refresh_desired(true); _apply_presentation_visibility()

# Pausing streaming is a quality-pressure action, not a presentation ownership change.
# Keep the current desired/active owners visible so FAR never has to replace an entire
# detail footprint in one frame. In-flight results are invalidated and drained without
# blocking the camera; resuming refreshes the viewport and reuses warm residents.
func set_streaming_enabled(value: bool) -> void:
	var next := value and _enabled and _ready
	if next == _streaming_enabled: return
	_streaming_enabled = next
	if not _streaming_enabled:
		_generation += 1; _queue.clear(); _queued.clear(); _ready_results.clear(); _trim_warm(); _trim_active_to_budget(); _apply_presentation_visibility(); coverage_changed.emit(); return
	_refresh_desired(true); _apply_presentation_visibility()

func set_presentation_visible(value: bool) -> void: _presentation_visible = value; _apply_presentation_visibility()

func _apply_presentation_visibility() -> void:
	for key_value in _active.keys():
		var key := String(key_value); var entry: Dictionary = _active[key]; var node := entry.get("node") as Node3D
		if node == null: continue
		var desired_lod := int(_desired.get(key, -1))
		var entry_lod := int(entry.get("lod", -1))
		var owns_region := _desired.has(key) and (entry_lod == desired_lod or not _has_ready_desired_owner(key, desired_lod))
		node.visible = _presentation_visible and _enabled and owns_region

func _has_ready_desired_owner(key: String, desired_lod: int) -> bool:
	if not _active.has(key): return false
	return int((_active[key] as Dictionary).get("lod", -1)) == desired_lod

func _touch_desired_residents() -> void:
	_resident_tick += 1
	for key_value in _desired.keys():
		var key := String(key_value)
		if _active.has(key):
			var entry: Dictionary = _active[key]
			entry["last_touch"] = _resident_tick; _active[key] = entry

static func choose_lru_stale_eviction_key(active: Dictionary, desired: Dictionary, publishing_key: String) -> String:
	var candidate := ""; var oldest := 9223372036854775807
	for key_value in active.keys():
		var key := String(key_value)
		if key == publishing_key or desired.has(key): continue
		var touch := int((active[key] as Dictionary).get("last_touch", 0))
		if candidate.is_empty() or touch < oldest or (touch == oldest and key < candidate): candidate = key; oldest = touch
	return candidate

func evict_warm_for_pressure(max_warm_cells: int = 0) -> int:
	# True warm LOD replacements are always the first quality sacrificed.
	var evicted := _warm.size()
	_clear_warm(true)
	var keep_warm := maxi(0, max_warm_cells)
	while _active.size() > _desired.size() + keep_warm:
		var stale := choose_lru_stale_eviction_key(_active, _desired, "")
		if stale.is_empty(): break
		_evict_active_key(stale); evicted += 1
	return evicted

func _prepare_resident_slot(key: String) -> bool:
	if _active.has(key): return true
	while _active.size() >= maxi(1, max_resident_cells):
		var stale := choose_lru_stale_eviction_key(_active, _desired, key)
		if stale.is_empty(): return false
		_evict_active_key(stale)
	return true

func _enforce_resident_budget() -> void:
	while _active.size() > maxi(1, max_resident_cells):
		var stale := choose_lru_stale_eviction_key(_active, _desired, "")
		if stale.is_empty(): break
		_evict_active_key(stale)

func _publish_cell(request: Dictionary, result: Dictionary) -> void:
	super._publish_cell(request, result)
	var key := String(request.get("key", ""))
	if _active.has(key):
		_resident_tick += 1; var entry: Dictionary = _active[key]; entry["last_touch"] = _resident_tick; _active[key] = entry
	_apply_presentation_visibility(); _enforce_resident_budget()

func _refresh_desired(force: bool) -> void: super._refresh_desired(force); _touch_desired_residents(); _apply_presentation_visibility(); _enforce_resident_budget()

func ready_desired_cells() -> int:
	var count := 0
	for key_value in _desired.keys():
		var key := String(key_value)
		if _active.has(key) and int((_active[key] as Dictionary).get("lod", -1)) == int(_desired[key]): count += 1
	return count

func _process(delta: float) -> void:
	if not _enabled: return
	_poll_queries()
	if not _streaming_enabled:
		_enforce_resident_budget(); return
	var started := Time.get_ticks_usec(); var published := 0; var budget := maxf(0.25,streaming_budget_ms)
	while not _ready_results.is_empty() and published < maxi(1,max_publishes_per_frame):
		if published > 0 and float(Time.get_ticks_usec()-started)/1000.0 >= budget: break
		_publish_one_ready_result(); published += 1
	_last_publish_frame_ms = float(Time.get_ticks_usec()-started)/1000.0 if published > 0 else 0.0
	if published > 0 and _last_publish_frame_ms > budget: _over_budget_publishes += 1
	_refresh_accum += delta
	if _refresh_accum >= refresh_interval_s: _refresh_accum=0.0; _refresh_desired(false)
	_enforce_resident_budget(); _start_queries_if_needed()

func debug_snapshot() -> Dictionary:
	var snapshot := super.debug_snapshot(); var ready_count := ready_desired_cells()
	snapshot["active_cells"] = ready_count; snapshot["ready_desired_cells"] = ready_count; snapshot["warm_resident_cells"] = _active.size() + _warm.size()
	snapshot["streaming_budget_ms"] = streaming_budget_ms; snapshot["last_publish_frame_ms"] = _last_publish_frame_ms; snapshot["over_budget_publishes"] = _over_budget_publishes; snapshot["presentation_visible"] = _presentation_visible
	return snapshot
