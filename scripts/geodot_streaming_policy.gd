extends RefCounted
class_name GeoDotStreamingPolicy

## Pure streaming policy for GeoDot presentation coverage.
## Keeps viewport coverage bounded by increasing query-cell scale instead of dropping visible world cells.

static func cell_range_for_bounds(bounds: Rect2, cell_size_m: float, margin_cells: int = 0) -> Rect2i:
	var size := maxf(1.0, cell_size_m)
	var margin := maxi(0, margin_cells)
	var min_cell := Vector2i(floori(bounds.position.x / size) - margin, floori(bounds.position.y / size) - margin)
	# Coverage is half-open at the maximum edge, matching source-cell ownership.
	# A zero-width/height bound still owns its containing cell.
	var max_point := bounds.position + bounds.size
	var max_x := floori(bounds.position.x / size) if bounds.size.x <= 0.0 else ceili(max_point.x / size) - 1
	var max_y := floori(bounds.position.y / size) if bounds.size.y <= 0.0 else ceili(max_point.y / size) - 1
	var max_cell := Vector2i(max_x + margin, max_y + margin)
	return Rect2i(min_cell, max_cell - min_cell + Vector2i.ONE)

static func cell_count_for_bounds(bounds: Rect2, cell_size_m: float, margin_cells: int = 0) -> int:
	var cell_range := cell_range_for_bounds(bounds, cell_size_m, margin_cells)
	return maxi(1, cell_range.size.x) * maxi(1, cell_range.size.y)

static func bounded_cell_size_for_bounds(bounds: Rect2, base_cell_size_m: float, margin_cells: int, max_cells: int) -> float:
	var size := maxf(1.0, base_cell_size_m)
	var limit := maxi(1, max_cells)
	while cell_count_for_bounds(bounds, size, margin_cells) > limit:
		size *= 2.0
	return size
