extends RefCounted
class_name GeoDotLodPolicy

const MODE_AGGREGATE := 0
const MODE_INDIVIDUAL := 1
const MODE_FULL_3D := 2

## Presentation-only policy. World/source identity never depends on these values.
static func meters_per_pixel(bounds: Rect2, viewport_size: Vector2) -> float:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return INF
	return maxf(bounds.size.x / viewport_size.x, bounds.size.y / viewport_size.y)

static func projected_pixels(world_size_m: float, meters_per_px: float) -> float:
	return maxf(0.0, world_size_m) / maxf(0.0001, meters_per_px)

static func representation_for_building(
	camera_distance_m: float,
	footprint_span_m: float,
	height_m: float,
	meters_per_px: float,
	individual_threshold_px: float,
	full_3d_threshold_px: float,
	full_3d_guarantee_m: float,
	tall_height_m: float,
	tall_3d_distance_m: float,
	individual_max_distance_m: float
) -> int:
	var distance := maxf(0.0, camera_distance_m)
	var projected_span := projected_pixels(maxf(footprint_span_m, height_m * 0.35), meters_per_px)
	if distance <= maxf(0.0, full_3d_guarantee_m):
		return MODE_FULL_3D
	if height_m >= tall_height_m and distance <= tall_3d_distance_m and projected_span >= individual_threshold_px:
		return MODE_FULL_3D
	if distance >= individual_max_distance_m:
		return MODE_AGGREGATE
	if projected_span >= full_3d_threshold_px:
		return MODE_FULL_3D
	if projected_span >= individual_threshold_px:
		return MODE_INDIVIDUAL
	return MODE_AGGREGATE

static func far_level_for_distance(distance_m: float, level_edges_m: PackedFloat64Array) -> int:
	var distance := maxf(0.0, distance_m)
	for index in range(level_edges_m.size()):
		if distance <= level_edges_m[index]:
			return index
	return level_edges_m.size()

static func sample_budget(base_budget: int, density_scale: float, hard_cap: int) -> int:
	return clampi(roundi(float(maxi(0, base_budget)) * maxf(0.0, density_scale)), 0, maxi(0, hard_cap))

static func ram_pressure(used_bytes: int, target_bytes: int, hard_cap_bytes: int) -> float:
	var target := maxi(1, target_bytes)
	var hard_cap := maxi(target, hard_cap_bytes)
	if used_bytes <= target:
		return 0.0
	return clampf(float(used_bytes - target) / float(maxi(1, hard_cap - target)), 0.0, 1.0)

static func quality_scale_for_pressure(pressure: float) -> float:
	# Keep at least 25% aggregate city signal under pressure; degrade detail first.
	return lerpf(1.0, 0.25, clampf(pressure, 0.0, 1.0))
