extends SceneTree

func _init() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/geodot_poc_tuned_main.gd")
	_assert(not source.is_empty(), "runtime composition source missing")
	_assert(source.contains("HlodResidency"), "runtime must consume HLOD residency core")
	_assert(source.contains("_hlod.visible_lod"), "runtime visibility must be driven by HLOD owner")
	_assert(not source.contains("TransitionPolicy.detail_owns_presentation"), "legacy global transition policy must not own runtime presentation")
	_assert(source.contains("return _base_ready and _hlod.has_coverage"), "activation must be gated by base coverage, not full detail")
	print("GEODOT_RUNTIME_HLOD_INTEGRATION=PASS runtime_owner=hlod base_gate=coverage")
	quit(0)

func _assert(value: bool, message: String) -> void:
	if value: return
	push_error(message)
	print("GEODOT_RUNTIME_HLOD_INTEGRATION=FAIL ",message)
	quit(1)
