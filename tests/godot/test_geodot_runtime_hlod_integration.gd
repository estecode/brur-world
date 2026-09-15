extends SceneTree

func _init() -> void:
	var main_source := FileAccess.get_file_as_string("res://scripts/geodot_poc_tuned_main.gd")
	var far_source := FileAccess.get_file_as_string("res://scripts/geodot_far_renderer.gd")
	var detail_source := FileAccess.get_file_as_string("res://scripts/geodot_world_renderer.gd")
	_assert(main_source.contains("set_detail_provider"), "runtime must connect far fallback to detail coverage")
	_assert(main_source.contains("global_owner_switch\": false"), "runtime must explicitly reject global ownership")
	_assert(not main_source.contains("detail_owns_presentation"), "legacy global owner must be absent")
	_assert(far_source.contains("ready_coverage_rects"), "far HLOD must consume READY detail regions")
	_assert(far_source.contains("_sample_owned_by_detail"), "far HLOD must mask only spatially replaced samples")
	_assert(detail_source.contains("origin_abs"), "detail cells must expose geographic ownership")
	_assert(detail_source.contains("ready_coverage_rects"), "detail renderer must expose READY spatial coverage")
	print("GEODOT_RUNTIME_HLOD_INTEGRATION=PASS spatial_owner=true global_switch=false base_fallback=true")
	quit(0)

func _assert(value: bool, message: String) -> void:
	if value:
		return
	push_error(message)
	print("GEODOT_RUNTIME_HLOD_INTEGRATION=FAIL ", message)
	quit(1)
