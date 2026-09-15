extends RefCounted
class_name GeoDotStreamingPolicy

## Pure streaming policy for GeoDot presentation coverage.
## Keeps viewport coverage bounded by increasing query-cell scale instead of dropping visible world cells.

static func cell_count_for_bounds(bounds: Rect2, cell_size_m: float, margin_cells: int = 0) -> int:
	var size := maxf(1.0, cell_size_m)
	var margin := maxi(0, margin_cells)
	var min_cell := Vector2i(floori(bounds.position.x / size) - margin, floori(bounds.position.y / size) - margin)
	var max_point := bounds.position + bounds.size
	var max_cell := Vector2i(floori(max_point.x / size) + margin, floori(max_point.y / size) + margin)
	return maxi(1, max_cell.x - min_cell.x + 1) * maxi(1, max_cell.y - min_cell.y + 1)

static func bounded_cell_size_for_bounds(bounds: Rect2, base_cell_size_m: float, margin_cells: int, max_cells: int) -> float:
	var size := maxf(1.0, base_cell_size_m)
	var limit := maxi(1, max_cells)
	while cell_count_for_bounds(bounds, size, margin_cells) > limit:
		size *= 2.0
	return size
