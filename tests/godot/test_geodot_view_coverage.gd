extends SceneTree

const Renderer = preload("res://scripts/geodot_world_renderer.gd")

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_assert(Renderer.coverage_radius_for_altitude(0.0, 3000.0, 3, 6, 0.72) == 3, "fallback ground view keeps baseline 7x7 coverage")
	_assert(Renderer.coverage_radius_for_altitude(9000.0, 3000.0, 3, 6, 0.72) == 4, "fallback 9 km view expands beyond the old fixed footprint")
	_assert(Renderer.coverage_radius_for_altitude(24000.0, 3000.0, 3, 6, 0.72) == 6, "fallback 24 km view reaches bounded 13x13 coverage")
	_assert(Renderer.coverage_radius_for_altitude(100000.0, 3000.0, 3, 6, 0.72) == 6, "fallback coverage remains explicitly bounded at extreme altitude")
	_test_viewport_bounds_follow_visible_region()
	_test_viewport_margin_preloads_outside_visible_region()
	_test_adaptive_cell_size_preserves_full_viewport()
	if _failed:
		quit(1)
		return
	print("geodot view coverage: OK")
	quit(0)

func _test_viewport_bounds_follow_visible_region() -> void:
	var cells := Renderer.coverage_cells_for_bounds(Rect2(Vector2(1000.0, 2000.0), Vector2(3500.0, 1500.0)), 1000.0, 0, 64, Vector2(2500.0, 2500.0))
	var expected := [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)]
	_assert(cells.size() == expected.size(), "viewport coverage uses the visible rectangular bounds rather than a fixed square radius")
	for cell in expected:
		_assert(cells.has(cell), "viewport coverage includes visible cell %s" % cell)
	_assert(not cells.has(Vector2i(0, 0)), "viewport coverage does not load unrelated cells around an altitude-derived square")

func _test_viewport_margin_preloads_outside_visible_region() -> void:
	var cells := Renderer.coverage_cells_for_bounds(Rect2(Vector2(2000.0, 2000.0), Vector2(1000.0, 1000.0)), 1000.0, 1, 64, Vector2(2500.0, 2500.0))
	_assert(cells.has(Vector2i(1, 1)) and cells.has(Vector2i(4, 4)), "viewport margin preloads one cell beyond the visible bounds")
	_assert(cells.size() == 16, "one-cell preload margin stays deterministic")

func _test_adaptive_cell_size_preserves_full_viewport() -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(100000.0, 70000.0))
	var cell_size := Renderer.coverage_cell_size_for_bounds(bounds, 3000.0, 1, 169)
	_assert(cell_size > 3000.0, "large viewport increases query-cell size instead of dropping visible coverage")
	var cells := Renderer.coverage_cells_for_bounds(bounds, cell_size, 1, 169, Vector2(50000.0, 35000.0))
	_assert(cells.size() <= 169, "adaptive viewport coverage obeys the resident bound")
	var min_cell := Vector2i(floori(bounds.position.x / cell_size) - 1, floori(bounds.position.y / cell_size) - 1)
	var max_point := bounds.position + bounds.size
	var max_cell := Vector2i(floori(max_point.x / cell_size) + 1, floori(max_point.y / cell_size) + 1)
	var expected_count := (max_cell.x - min_cell.x + 1) * (max_cell.y - min_cell.y + 1)
	_assert(cells.size() == expected_count, "resident bound never truncates the visible viewport after adaptive sizing")
	_assert(cells.has(min_cell) and cells.has(max_cell), "adaptive coverage includes both viewport extremes plus preload margin")

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("ASSERT FAILED: " + message)
