extends RefCounted
class_name GeoDotTransitionPolicy

static func prefetch_distance(far_distance_m: float, prefetch_scale: float) -> float:
	return maxf(0.0,far_distance_m) * clampf(prefetch_scale,1.0,3.0)

static func detail_ready(snapshot: Dictionary) -> bool:
	var desired := int(snapshot.get("desired_cells",0))
	var active := int(snapshot.get("active_cells",0))
	if desired <= 0 or active <= 0: return false
	# The transition needs useful viewport coverage, not complete settlement.
	# Requiring every desired cell recreates the old high-altitude stall.
	var minimum := mini(desired,9)
	return active >= minimum

static func hold_far(distance_m: float, far_distance_m: float, detail_prefetching: bool, detail_is_ready: bool) -> bool:
	if distance_m >= far_distance_m: return false
	return detail_prefetching and not detail_is_ready
