extends "res://scripts/geodot_poc_main.gd"

const LodPolicy = preload("res://scripts/geodot_lod_policy.gd")
const FAR_PRESENTATION_M := 55000.0
const ORDINARY_BUILDING_M := 10.0
const TALL_BUILDING_M := 30.0

var _effective_resident_cells := 128
var _base_ready := false
var _loading_layer: CanvasLayer = null
var _loading_label: Label = null
var _ram_hard_pressure := false

func _ready() -> void:
	_create_loading_gate()
	super._ready()
	if not _geodot_ready:
		_disable_loading_gate_for_legacy(); return
	if geodot_far_layer != null and geodot_far_layer.has_method("set_detail_provider"):
		geodot_far_layer.call("set_detail_provider", geodot_world_layer)
	if geodot_far_layer == null or not geodot_far_layer.has_method("is_cache_ready") or not bool(geodot_far_layer.call("is_cache_ready")):
		push_warning("GeoDot base HLOD unavailable; keeping legacy world presentation")
		_geodot_ready = false; _geodot_activation_pending = false
		if geodot_world_layer != null and geodot_world_layer.has_method("set_enabled"): geodot_world_layer.call("set_enabled", false)
		_disable_loading_gate_for_legacy(); return
	if geodot_world_layer != null and geodot_world_layer.has_method("set_presentation_visible"): geodot_world_layer.call("set_presentation_visible", true)
	_refresh_base_readiness()

func _create_loading_gate() -> void:
	_loading_layer = CanvasLayer.new(); _loading_layer.name = "GeoDotPreparingWorld"; _loading_layer.layer = 1000; add_child(_loading_layer)
	var background := ColorRect.new(); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); background.color = Color(0.025, 0.028, 0.032, 1.0); background.mouse_filter = Control.MOUSE_FILTER_STOP; _loading_layer.add_child(background)
	_loading_label = Label.new(); _loading_label.text = "Preparing world…"; _loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; _loading_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); background.add_child(_loading_label)

func _disable_loading_gate_for_legacy() -> void:
	if _loading_layer != null: _loading_layer.visible = false

func _refresh_base_readiness() -> void:
	_base_ready = _geodot_ready and geodot_far_layer != null and geodot_far_layer.has_method("is_coverage_ready") and bool(geodot_far_layer.call("is_coverage_ready"))
	if _loading_label != null: _loading_label.text = "Preparing world…" if not _base_ready else "World ready"

func _apply_tuning() -> void:
	super._apply_tuning()
	if geodot_world_layer != null:
		geodot_world_layer.set("streaming_budget_ms", clampf(float(_tuning.get("streaming_ms", 3.0)), 0.25, 12.0))
		geodot_world_layer.set("far_enter_pixels", clampf(float(_tuning.get("individual_threshold_px", 1.0)), 0.1, 16.0))
		geodot_world_layer.set("far_exit_pixels", clampf(float(_tuning.get("full_3d_threshold_px", 4.0)), 0.2, 32.0))

func _process(delta: float) -> void:
	_refresh_base_readiness(); super._process(delta)
	if _geodot_active and _base_ready and _loading_layer != null: _loading_layer.visible = false

func _geodot_activation_coverage_ready() -> bool:
	return _base_ready

func _update_distance_policy() -> void:
	if not _geodot_ready: return
	var distance := _camera_distance_to_focus()
	var full_3d_distance := maxf(250.0, float(_tuning.get("full_3d_distance_m", 3000.0)))
	var tall_3d_distance := maxf(full_3d_distance, float(_tuning.get("tall_3d_distance_m", 6000.0)))
	var full_threshold := clampf(float(_tuning.get("full_3d_threshold_px", 4.0)), 0.2, 32.0)
	geodot_world_layer.set("far_exit_pixels", -1.0 if distance <= full_3d_distance else full_threshold)
	geodot_world_layer.set("representative_building_m", TALL_BUILDING_M if distance <= tall_3d_distance and distance > full_3d_distance else ORDINARY_BUILDING_M)
	var base_resident := clampi(int(_tuning.get("resident_cells", 128)), 16, 169)
	var target_bytes := maxi(256, int(_tuning.get("ram_target_mb", 2048))) * 1024 * 1024
	var hard_bytes := maxi(int(_tuning.get("ram_target_mb", 2048)), int(_tuning.get("ram_hard_mb", 2560))) * 1024 * 1024
	var pressure := LodPolicy.ram_pressure(int(Performance.get_monitor(Performance.MEMORY_STATIC)), target_bytes, hard_bytes)
	_ram_hard_pressure = pressure >= 1.0
	_effective_resident_cells = clampi(roundi(float(base_resident) * LodPolicy.quality_scale_for_pressure(pressure)), 16, base_resident)
	geodot_world_layer.set("max_resident_cells", _effective_resident_cells)
	var prefetch_distance := maxf(tall_3d_distance, full_3d_distance * clampf(float(_tuning.get("prefetch_scale", 1.35)), 1.0, 3.0))
	# Far HLOD is already complete coverage. Query expensive individual geometry only
	# while it can become visible soon; this keeps 500 km zooms photographic instead
	# of spending the worker queue on detail that cannot improve the current frame.
	var want_detail := distance <= prefetch_distance and not _ram_hard_pressure
	if want_detail != _detail_streaming_enabled:
		_detail_streaming_enabled = want_detail; geodot_world_layer.call("set_enabled", want_detail)
	if _ram_hard_pressure and geodot_world_layer.has_method("evict_warm_for_pressure"):
		geodot_world_layer.call("evict_warm_for_pressure", 0)
	if geodot_world_layer.has_method("set_presentation_visible"): geodot_world_layer.call("set_presentation_visible", true)

func geodot_debug_snapshot() -> Dictionary:
	var snapshot := super.geodot_debug_snapshot()
	snapshot["spatial_hlod"] = {"base_ready": _base_ready, "initial_view_covered": _base_ready, "loading_gate_visible": _loading_layer != null and _loading_layer.visible, "ready_detail_regions": geodot_world_layer.call("ready_coverage_rects").size() if geodot_world_layer != null and geodot_world_layer.has_method("ready_coverage_rects") else 0, "global_owner_switch": false, "effective_resident_cells": _effective_resident_cells, "ram_hard_pressure": _ram_hard_pressure, "tall_3d_distance_m": float(_tuning.get("tall_3d_distance_m", 6000.0)), "detail_prefetch_distance_m": maxf(float(_tuning.get("tall_3d_distance_m", 6000.0)), float(_tuning.get("full_3d_distance_m", 3000.0)) * clampf(float(_tuning.get("prefetch_scale", 1.35)), 1.0, 3.0))}
	return snapshot
