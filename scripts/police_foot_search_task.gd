class_name PoliceFootSearchTask
extends RefCounted

## Selects one deterministic local search point for an officer from a derived search area.
##
## Dependencies:
## - Consumes PoliceFootSearchArea-shaped dictionaries and caller-provided officer position.
## - Owns no player state, Person physics, routing graph, SceneTree, or rendering.

func choose(search_area: Dictionary, officer_position: Vector2) -> Dictionary:
	if search_area.is_empty() or not officer_position.is_finite():
		return {}
	var candidates_value: Variant = search_area.get("candidates", [])
	if not candidates_value is Array:
		return {}
	var center: Vector2 = search_area.get("center", Vector2(INF, INF))
	var best := Vector2(INF, INF)
	var best_distance := INF
	for candidate_value in candidates_value:
		if not candidate_value is Vector2:
			continue
		var candidate := candidate_value as Vector2
		if not candidate.is_finite():
			continue
		if candidates_value.size() > 1 and center.is_finite() and candidate.is_equal_approx(center):
			continue
		var distance := officer_position.distance_squared_to(candidate)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	if not best.is_finite() and center.is_finite():
		best = center
	if not best.is_finite():
		return {}
	return {
		"target_position": best,
		"search_radius_m": float(search_area.get("radius_m", 0.0)),
		"source_timestamp_s": float(search_area.get("source_timestamp_s", 0.0)),
		"confidence": float(search_area.get("confidence", 1.0)),
	}
