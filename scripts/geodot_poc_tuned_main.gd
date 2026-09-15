extends "res://scripts/geodot_poc_main.gd"

const TransitionPolicy = preload("res://scripts/geodot_transition_policy.gd")
const LodPolicy = preload("res://scripts/geodot_lod_policy.gd")
const FAR_PRESENTATION_M := 55000.0
const ORDINARY_BUILDING_M := 10.0
const TALL_BUILDING_M := 30.0

var _transition_prefetching := false
var _transition_detail_ready := false
var _effective_resident_cells := 128

func _apply_tuning() -> void:
	super._apply_tuning()
	if geodot_world_layer != null:
		geodot_world_layer.set("streaming_budget_ms",clampf(float(_tuning.get("streaming_ms",3.0)),0.25,12.0))
		geodot_world_layer.set("far_enter_pixels",clampf(float(_tuning.get("individual_threshold_px",1.0)),0.1,16.0))
		geodot_world_layer.set("far_exit_pixels",clampf(float(_tuning.get("full_3d_threshold_px",4.0)),0.2,32.0))

func _update_distance_policy() -> void:
	if not _geodot_ready: return
	var distance := _camera_distance_to_focus()
	var full_3d_distance := maxf(250.0,float(_tuning.get("full_3d_distance_m",3000.0)))
	var tall_3d_distance := maxf(full_3d_distance,float(_tuning.get("tall_3d_distance_m",6000.0)))
	var full_threshold := clampf(float(_tuning.get("full_3d_threshold_px",4.0)),0.2,32.0)
	geodot_world_layer.set("far_exit_pixels",-1.0 if distance<=full_3d_distance else full_threshold)
	# Between the ordinary and tall retention distances the screen-space decision
	# is evaluated using a representative tall structure. This deliberately keeps
	# conspicuous skyline mass in the detailed batch longer without changing the
	# guaranteed 3 km ordinary-building rule.
	geodot_world_layer.set("representative_building_m",TALL_BUILDING_M if distance<=tall_3d_distance and distance>full_3d_distance else ORDINARY_BUILDING_M)

	var base_resident := clampi(int(_tuning.get("resident_cells",128)),16,169)
	var target_bytes := maxi(256,int(_tuning.get("ram_target_mb",2048)))*1024*1024
	var hard_bytes := maxi(int(_tuning.get("ram_target_mb",2048)),int(_tuning.get("ram_hard_mb",2560)))*1024*1024
	var pressure := LodPolicy.ram_pressure(int(Performance.get_monitor(Performance.MEMORY_STATIC)),target_bytes,hard_bytes)
	_effective_resident_cells = clampi(roundi(float(base_resident)*LodPolicy.quality_scale_for_pressure(pressure)),16,base_resident)
	geodot_world_layer.set("max_resident_cells",_effective_resident_cells)

	var prefetch_scale := clampf(float(_tuning.get("prefetch_scale",1.35)),1.0,3.0)
	var prefetch_distance := TransitionPolicy.prefetch_distance(FAR_PRESENTATION_M,prefetch_scale)
	var want_detail := distance <= prefetch_distance
	if want_detail != _detail_streaming_enabled:
		_detail_streaming_enabled = want_detail; geodot_world_layer.call("set_enabled",want_detail); _transition_prefetching = want_detail; _transition_detail_ready = false
	if want_detail: _transition_detail_ready = TransitionPolicy.detail_ready(geodot_world_layer.call("debug_snapshot"))
	else: _transition_detail_ready = false
	if geodot_far_layer != null and geodot_far_layer.has_method("set_transition_hold"):
		geodot_far_layer.call("set_transition_hold",TransitionPolicy.hold_far(distance,FAR_PRESENTATION_M,want_detail,_transition_detail_ready))

func geodot_debug_snapshot() -> Dictionary:
	var snapshot := super.geodot_debug_snapshot()
	snapshot["transition"] = {"prefetching":_transition_prefetching,"detail_ready":_transition_detail_ready,"prefetch_scale":float(_tuning.get("prefetch_scale",1.35)),"prefetch_distance_m":TransitionPolicy.prefetch_distance(FAR_PRESENTATION_M,float(_tuning.get("prefetch_scale",1.35))),"effective_resident_cells":_effective_resident_cells,"tall_3d_distance_m":float(_tuning.get("tall_3d_distance_m",6000.0))}
	return snapshot
