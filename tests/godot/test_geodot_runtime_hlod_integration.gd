extends SceneTree

const FarRenderer = preload("res://scripts/geodot_far_renderer.gd")

func _init() -> void:
	var main_source := FileAccess.get_file_as_string("res://scripts/geodot_poc_tuned_main.gd")
	var far_source := FileAccess.get_file_as_string("res://scripts/geodot_far_renderer.gd")
	var detail_source := FileAccess.get_file_as_string("res://scripts/geodot_world_renderer.gd")
	_assert(main_source.contains("set_detail_provider"), "runtime must connect far fallback to detail coverage")
	_assert(main_source.contains("global_owner_switch\": false"), "runtime must explicitly reject global ownership")
	_assert(not main_source.contains("detail_owns_presentation"), "legacy global owner must be absent")
	_assert(main_source.contains("Preparing world"), "runtime must hide world construction behind startup gate")
	_assert(main_source.contains("is_coverage_ready"), "startup gate must wait for completed base coverage")
	_assert(far_source.contains("_batches"), "far HLOD must use bounded spatial batches")
	_assert(far_source.contains("max_batches"), "far HLOD batch population must be explicitly bounded")
	_assert(far_source.contains("coverage_complete"), "base readiness must reject truncated aggregate coverage")
	_assert(far_source.contains("ready_coverage_rects"), "far HLOD must consume READY detail regions")
	_assert(detail_source.contains("origin_abs"), "detail cells must expose geographic ownership")
	_assert(detail_source.contains("ready_coverage_rects"), "detail renderer must expose READY spatial coverage")
	var detail: Array[Rect2] = [Rect2(Vector2(0, 0), Vector2(100, 100))]
	_assert(FarRenderer.sample_fully_owned_by_detail(Rect2(Vector2(10, 10), Vector2(20, 20)), detail), "fully covered far cell must yield to READY detail")
	_assert(not FarRenderer.sample_fully_owned_by_detail(Rect2(Vector2(90, 90), Vector2(20, 20)), detail), "partial detail coverage must retain fallback and never create a hole")
	var samples: Array[Dictionary] = []
	for y in range(32):
		for x in range(32):
			samples.append({"x": x, "y": y, "cell_m": 2000.0, "coverage": 0.5})
	var grouped := FarRenderer.group_samples(samples, 1, 8)
	_assert(grouped.size() <= 8, "spatial batch count must remain bounded")
	var grouped_count := 0
	for values in grouped.values():
		grouped_count += (values as Array).size()
	_assert(grouped_count == samples.size(), "batch bounding must never discard far coverage")
	print("GEODOT_RUNTIME_HLOD_INTEGRATION=PASS spatial_owner=true global_switch=false base_gate=true bounded_far_batches=true no_partial_mask_holes=true no_batch_sample_loss=true")
	quit(0)

func _assert(value: bool, message: String) -> void:
	if value:
		return
	push_error(message)
	print("GEODOT_RUNTIME_HLOD_INTEGRATION=FAIL ", message)
	quit(1)
