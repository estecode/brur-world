extends SceneTree

const Renderer = preload("res://scripts/geodot_world_renderer.gd")
var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_viewport_bounds_follow_visible_region()
	_test_exact_boundary_is_half_open()
	_test_viewport_margin_preloads_outside_visible_region()
	_test_large_view_keeps_stable_tiles_and_bounded_detail()
	if _failed:
		quit(1); return
	print("geodot view coverage: OK stable_tiles=true bounded_detail=true")
	quit(0)

func _test_viewport_bounds_follow_visible_region() -> void:
	var cells := Renderer.coverage_cells_for_bounds(Rect2(Vector2(1000.0, 2000.0), Vector2(3500.0, 1500.0)), 1000.0, 0, 64, Vector2(2500.0, 2500.0))
	var expected := [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)]
	_assert(cells.size() == expected.size(), "detail follows visible rectangular bounds")
	for cell in expected: _assert(cells.has(cell), "visible cell is represented")

func _test_exact_boundary_is_half_open() -> void:
	var cells := Renderer.coverage_cells_for_bounds(Rect2(Vector2(2000.0, 2000.0), Vector2(1000.0, 1000.0)), 1000.0, 0, 64, Vector2(2500.0, 2500.0))
	_assert(cells == [Vector2i(2, 2)], "exact maximum boundary is half-open")

func _test_viewport_margin_preloads_outside_visible_region() -> void:
	var cells := Renderer.coverage_cells_for_bounds(Rect2(Vector2(2000.0, 2000.0), Vector2(1000.0, 1000.0)), 1000.0, 1, 64, Vector2(2500.0, 2500.0))
	_assert(cells.has(Vector2i(1, 1)) and cells.has(Vector2i(3, 3)), "margin preloads adjacent tiles")
	_assert(cells.size() == 9, "margin remains deterministic")

func _test_large_view_keeps_stable_tiles_and_bounded_detail() -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(100000.0, 70000.0))
	var cell_size := Renderer.coverage_cell_size_for_bounds(bounds, 3000.0, 1, 169)
	_assert(is_equal_approx(cell_size, 3000.0), "zoom never changes geographic detail-tile identity")
	var focus := Vector2(50000.0, 35000.0)
	var cells := Renderer.coverage_cells_for_bounds(bounds, cell_size, 1, 169, focus)
	_assert(cells.size() == 169, "detail work is capped while base HLOD owns the rest of the view")
	var focus_cell := Vector2i(floori(focus.x / cell_size), floori(focus.y / cell_size))
	_assert(cells.has(focus_cell), "bounded detail prioritizes camera focus")

func _assert(condition: bool, message: String) -> void:
	if condition: return
	_failed = true; push_error("ASSERT FAILED: " + message)
