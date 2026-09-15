extends "res://scripts/geodot_poc_main.gd"

const DETAIL_DISABLE_M := 60000.0
const DETAIL_REENABLE_M := 50000.0

func _apply_tuning() -> void:
	super._apply_tuning()
	if geodot_world_layer != null:
		geodot_world_layer.set("streaming_budget_ms",clampf(float(_tuning.get("streaming_ms",3.0)),0.25,12.0))
		geodot_world_layer.set("far_enter_pixels",clampf(float(_tuning.get("individual_threshold_px",1.0)),0.1,16.0))
		geodot_world_layer.set("far_exit_pixels",clampf(float(_tuning.get("full_3d_threshold_px",4.0)),0.2,32.0))

func _update_distance_policy() -> void:
	if not _geodot_ready: return
	var distance := _camera_distance_to_focus(); var full_3d_distance:=maxf(250.0,float(_tuning.get("full_3d_distance_m",3000.0)))
	var full_threshold:=clampf(float(_tuning.get("full_3d_threshold_px",4.0)),0.2,32.0)
	geodot_world_layer.set("far_exit_pixels",-1.0 if distance<=full_3d_distance else full_threshold)
	if _detail_streaming_enabled and distance>=DETAIL_DISABLE_M:
		_detail_streaming_enabled=false; geodot_world_layer.call("set_enabled",false)
	elif not _detail_streaming_enabled and distance<=DETAIL_REENABLE_M:
		_detail_streaming_enabled=true; geodot_world_layer.call("set_enabled",true)
