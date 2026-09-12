class_name RoadLodPolicy
extends RefCounted

## Owns road presentation LOD, physical widths, and bounded tile-build scheduling.
##
## Dependencies:
## - Pure policy only; does not depend on scene state, rendering nodes, or world data I/O.

const ROAD_WIDTHS_M: Array[float] = [24.0, 18.0, 12.0, 9.0, 7.0, 5.5, 4.0]
const BUILD_BUDGET_MS: float = 3.0
const MAX_TILES_PER_FRAME: int = 12

static func road_width_m(road_class: int) -> float:
	var index := clampi(road_class, 0, ROAD_WIDTHS_M.size() - 1)
	return ROAD_WIDTHS_M[index]

static func choose_lod(view_distance_m: float, current_lod: int) -> int:
	if current_lod < 0:
		if view_distance_m > 180000.0:
			return 0
		if view_distance_m > 45000.0:
			return 1
		return 2
	if current_lod == 0:
		if view_distance_m < 155000.0:
			return 1
		return 0
	if current_lod == 1:
		if view_distance_m > 205000.0:
			return 0
		if view_distance_m < 38000.0:
			return 2
		return 1
	if view_distance_m > 56000.0:
		return 1
	return 2

static func can_build_more(elapsed_ms: float, tiles_built: int) -> bool:
	if tiles_built <= 0:
		return true
	return tiles_built < MAX_TILES_PER_FRAME and elapsed_ms < BUILD_BUDGET_MS
