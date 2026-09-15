extends RefCounted
class_name GeoDotTransitionPolicy

static func prefetch_distance(far_distance_m: float, prefetch_scale: float) -> float:
	return maxf(0.0,far_distance_m) * clampf(prefetch_scale,1.0,3.0)

static func detail_ready(snapshot: Dictionary) -> bool:
	var desired := int(snapshot.get("desired_cells",0))
	var ready := int(snapshot.get("ready_desired_cells", snapshot.get("active_cells",0)))
	if desired <= 0: return false
	# A presentation owner may change only when the complete requested coverage is
	# resident. Partial readiness is useful for prefetch, never for visibility: it
	# caused far/detail overlap, holes and flicker during fast zoom.
	return ready >= desired

static func detail_owns_presentation(distance_m: float, far_distance_m: float, detail_prefetching: bool, detail_is_ready: bool) -> bool:
	return distance_m < far_distance_m and detail_prefetching and detail_is_ready

static func hold_far(distance_m: float, far_distance_m: float, detail_prefetching: bool, detail_is_ready: bool) -> bool:
	if distance_m >= far_distance_m: return false
	return detail_prefetching and not detail_is_ready
