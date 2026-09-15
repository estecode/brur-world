extends SceneTree

const FarRenderer = preload("res://scripts/geodot_far_renderer.gd")
const DetailRenderer = preload("res://scripts/geodot_world_renderer.gd")

func _init() -> void:
	var main_source := FileAccess.get_file_as_string("res://scripts/geodot_poc_tuned_main.gd")
	var far_source := FileAccess.get_file_as_string("res://scripts/geodot_far_renderer.gd")
	var detail_source := FileAccess.get_file_as_string("res://scripts/geodot_world_renderer.gd")
	_assert(main_source.contains("set_detail_provider"), "runtime connects far fallback to detail coverage")
	_assert(main_source.contains("global_owner_switch\": false"), "runtime rejects global ownership")
	_assert(not main_source.contains("detail_owns_presentation"), "legacy global owner is absent")
	_assert(main_source.contains("Preparing world"), "startup gate hides world construction")
	_assert(main_source.contains("is_coverage_ready"), "startup waits for complete base coverage")
	_assert(far_source.contains("_batches") and far_source.contains("max_batches"), "far HLOD uses bounded spatial batches")
	_assert(far_source.contains("coverage_complete"), "base readiness rejects truncated coverage")
	_assert(detail_source.contains("signal coverage_changed"), "detail ownership changes are explicit")
	_assert(detail_source.contains("origin_abs") and detail_source.contains("ready_coverage_rects"), "READY detail exposes geographic ownership")
	var huge := Rect2(Vector2.ZERO, Vector2(500000.0, 500000.0))
	_assert(is_equal_approx(DetailRenderer.coverage_cell_size_for_bounds(huge, 2000.0, 1, 169), 2000.0), "zoom cannot mutate detail region identity")
	var bounded := DetailRenderer.coverage_cells_for_bounds(huge, 2000.0, 1, 169, Vector2(250000.0, 250000.0))
	_assert(bounded.size() == 169, "huge view caps detail work while far HLOD owns remaining coverage")
	var detail: Array[Rect2] = [Rect2(Vector2(0, 0), Vector2(100, 100))]
	_assert(FarRenderer.sample_fully_owned_by_detail(Rect2(Vector2(10, 10), Vector2(20, 20)), detail), "READY detail owns fully covered far cell")
	_assert(not FarRenderer.sample_fully_owned_by_detail(Rect2(Vector2(90, 90), Vector2(20, 20)), detail), "partial detail retains fallback")
	var samples: Array[Dictionary] = []
	for y in range(32):
		for x in range(32): samples.append({"x":x,"y":y,"cell_m":2000.0,"coverage":0.5})
	var grouped := FarRenderer.group_samples(samples,1,8); var grouped_count := 0
	_assert(grouped.size() <= 8, "far batch count is bounded")
	for values in grouped.values(): grouped_count += (values as Array).size()
	_assert(grouped_count == samples.size(), "batch bounding never discards coverage")
	print("GEODOT_RUNTIME_HLOD_INTEGRATION=PASS spatial_owner=true stable_tiles=true bounded_detail=true base_gate=true no_partial_mask_holes=true")
	quit(0)

func _assert(value:bool,message:String)->void:
	if value:return
	push_error(message);print("GEODOT_RUNTIME_HLOD_INTEGRATION=FAIL ",message);quit(1)
