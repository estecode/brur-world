extends "res://scripts/geodot_poc_main.gd"

const LodPolicy = preload("res://scripts/geodot_lod_policy.gd")
const FAR_PRESENTATION_M := 55000.0
const ORDINARY_BUILDING_M := 10.0
const TALL_BUILDING_M := 30.0
var _effective_resident_cells := 128
var _base_ready := false

func _ready() -> void:
	super._ready()
	# Far cache is the always-ready base coverage. Detail owns only cells whose
	# replacement mesh is already READY; the far renderer masks those cells.
	if geodot_far_layer != null and geodot_far_layer.has_method("set_detail_provider"):
		geodot_far_layer.call("set_detail_provider", geodot_world_layer)
	_base_ready = geodot_far_layer != null
	if geodot_world_layer != null and geodot_world_layer.has_method("set_presentation_visible"):
		geodot_world_layer.call("set_presentation_visible", true)

func _apply_tuning() -> void:
	super._apply_tuning()
	if geodot_world_layer != null:
		geodot_world_layer.set("streaming_budget_ms", clampf(float(_tuning.get("streaming_ms", 3.0)), 0.25, 12.0))
		geodot_world_layer.set("far_enter_pixels", clampf(float(_tuning.get("individual_threshold_px", 1.0)), 0.1, 16.0))
		geodot_world_layer.set("far_exit_pixels", clampf(float(_tuning.get("full_3d_threshold_px", 4.0)), 0.2, 32.0))

func _geodot_activation_coverage_ready() -> bool:
	# Gameplay can be presented as soon as the base HLOD exists. Detail is never
	# a startup dependency and can only replace base coverage after publication.
	return _base_ready

func _update_distance_policy() -> void:
	if not _geodot_ready:
		return
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
	_effective_resident_cells = clampi(roundi(float(base_resident) * LodPolicy.quality_scale_for_pressure(pressure)), 16, base_resident)
	geodot_world_layer.set("max_resident_cells", _effective_resident_cells)
	var prefetch_distance := FAR_PRESENTATION_M * clampf(float(_tuning.get("prefetch_scale", 1.35)), 1.0, 3.0)
	var want_detail := distance <= prefetch_distance
	if want_detail != _detail_streaming_enabled:
		_detail_streaming_enabled = want_detail
		geodot_world_layer.call("set_enabled", want_detail)
	# No global presentation switch. Far remains resident and visible everywhere
	# except READY detail rectangles; detail remains visible for READY cells.
	if geodot_world_layer.has_method("set_presentation_visible"):
		geodot_world_layer.call("set_presentation_visible", true)

func geodot_debug_snapshot() -> Dictionary:
	var snapshot := super.geodot_debug_snapshot()
	snapshot["spatial_hlod"] = {
		"base_ready": _base_ready,
		"ready_detail_regions": geodot_world_layer.call("ready_coverage_rects").size() if geodot_world_layer != null and geodot_world_layer.has_method("ready_coverage_rects") else 0,
		"global_owner_switch": false,
		"effective_resident_cells": _effective_resident_cells,
		"tall_3d_distance_m": float(_tuning.get("tall_3d_distance_m", 6000.0))
	}
	return snapshot
