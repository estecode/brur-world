extends "res://scripts/geodot_poc_main.gd"

const DETAIL_DISABLE_M := 60000.0
const DETAIL_REENABLE_M := 50000.0
const FULL_3D_GUARANTEE_M := 3000.0

func _update_distance_policy() -> void:
	if not _geodot_ready: return
	var distance := _camera_distance_to_focus()
	geodot_world_layer.set("far_exit_pixels", -1.0 if distance <= FULL_3D_GUARANTEE_M else 2.25)
	if _detail_streaming_enabled and distance >= DETAIL_DISABLE_M:
		_detail_streaming_enabled=false; geodot_world_layer.call("set_enabled",false)
	elif not _detail_streaming_enabled and distance <= DETAIL_REENABLE_M:
		_detail_streaming_enabled=true; geodot_world_layer.call("set_enabled",true)
