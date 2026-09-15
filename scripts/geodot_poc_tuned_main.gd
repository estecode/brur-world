extends "res://scripts/geodot_poc_main.gd"

const LodPolicy = preload("res://scripts/geodot_lod_policy.gd")
const HlodResidency = preload("res://scripts/geodot_hlod_residency.gd")
const FAR_PRESENTATION_M := 55000.0
const ORDINARY_BUILDING_M := 10.0
const TALL_BUILDING_M := 30.0

var _effective_resident_cells := 128
var _hlod := HlodResidency.new()
var _base_ready := false

func _ready() -> void:
	# The far aggregate is the mandatory base representation. Gameplay presentation
	# is never allowed to depend on detail streaming completing.
	_hlod.register_base("world", 0)
	_base_ready = true
	super._ready()
	_apply_hlod_ownership()

func _apply_tuning() -> void:
	super._apply_tuning()
	if geodot_world_layer != null:
		geodot_world_layer.set("streaming_budget_ms",clampf(float(_tuning.get("streaming_ms",3.0)),0.25,12.0))
		geodot_world_layer.set("far_enter_pixels",clampf(float(_tuning.get("individual_threshold_px",1.0)),0.1,16.0))
		geodot_world_layer.set("far_exit_pixels",clampf(float(_tuning.get("full_3d_threshold_px",4.0)),0.2,32.0))

func _geodot_activation_coverage_ready() -> bool:
	# Base HLOD is the bounded readiness contract; detail is refinement only.
	return _base_ready and _hlod.has_coverage("world")

func _update_distance_policy() -> void:
	if not _geodot_ready: return
	var distance := _camera_distance_to_focus()
	var full_3d_distance := maxf(250.0,float(_tuning.get("full_3d_distance_m",3000.0)))
	var tall_3d_distance := maxf(full_3d_distance,float(_tuning.get("tall_3d_distance_m",6000.0)))
	var full_threshold := clampf(float(_tuning.get("full_3d_threshold_px",4.0)),0.2,32.0)
	geodot_world_layer.set("far_exit_pixels",-1.0 if distance<=full_3d_distance else full_threshold)
	geodot_world_layer.set("representative_building_m",TALL_BUILDING_M if distance<=tall_3d_distance and distance>full_3d_distance else ORDINARY_BUILDING_M)

	var base_resident := clampi(int(_tuning.get("resident_cells",128)),16,169)
	var target_bytes := maxi(256,int(_tuning.get("ram_target_mb",2048)))*1024*1024
	var hard_bytes := maxi(int(_tuning.get("ram_target_mb",2048)),int(_tuning.get("ram_hard_mb",2560)))*1024*1024
	var pressure := LodPolicy.ram_pressure(int(Performance.get_monitor(Performance.MEMORY_STATIC)),target_bytes,hard_bytes)
	_effective_resident_cells = clampi(roundi(float(base_resident)*LodPolicy.quality_scale_for_pressure(pressure)),16,base_resident)
	geodot_world_layer.set("max_resident_cells",_effective_resident_cells)

	var prefetch_scale := clampf(float(_tuning.get("prefetch_scale",1.35)),1.0,3.0)
	var prefetch_distance := FAR_PRESENTATION_M * prefetch_scale
	var want_detail := distance <= prefetch_distance
	if want_detail != _detail_streaming_enabled:
		_detail_streaming_enabled = want_detail
		geodot_world_layer.call("set_enabled",want_detail)
	_hlod.set_desired_lod("world",1 if distance < FAR_PRESENTATION_M else 0)
	if want_detail:
		_hlod.request("world",1)
		var snapshot: Dictionary = geodot_world_layer.call("debug_snapshot")
		var desired := int(snapshot.get("desired_cells",0))
		var ready := int(snapshot.get("ready_desired_cells",snapshot.get("active_cells",0)))
		if desired > 0 and ready >= desired:
			_hlod.mark_ready("world",1)
	_apply_hlod_ownership()

func _apply_hlod_ownership() -> void:
	var detail_owner := _hlod.visible_lod("world") == 1
	if geodot_world_layer != null and geodot_world_layer.has_method("set_presentation_visible"):
		geodot_world_layer.call("set_presentation_visible",detail_owner)
	if geodot_far_layer != null:
		if geodot_far_layer.has_method("set_detail_owner"): geodot_far_layer.call("set_detail_owner",detail_owner)
		if geodot_far_layer.has_method("set_transition_hold"): geodot_far_layer.call("set_transition_hold",not detail_owner)

func geodot_debug_snapshot() -> Dictionary:
	var snapshot := super.geodot_debug_snapshot()
	snapshot["hlod"] = _hlod.snapshot()
	snapshot["hlod"]["visible_lod"] = _hlod.visible_lod("world")
	snapshot["hlod"]["base_ready"] = _base_ready
	snapshot["transition"] = {"detail_owner":_hlod.visible_lod("world")==1,"effective_resident_cells":_effective_resident_cells,"tall_3d_distance_m":float(_tuning.get("tall_3d_distance_m",6000.0))}
	return snapshot
