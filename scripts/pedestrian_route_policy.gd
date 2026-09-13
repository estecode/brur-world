class_name PedestrianRoutePolicy
extends RefCounted

## Ranks externally supplied route candidates for ordinary pedestrian behavior.
##
## Dependencies:
## - Consumes candidate segments produced by a world/routing owner; it does not build or own another graph.
## - Has no SceneTree, Person physics, rendering, player, traffic, or police dependency.

const FOOTWAY: StringName = &"footway"
const PEDESTRIAN: StringName = &"pedestrian"
const SIDEWALK: StringName = &"sidewalk"
const CROSSING: StringName = &"crossing"
const PATH: StringName = &"path"
const PLAZA: StringName = &"plaza"
const OPEN_GROUND: StringName = &"open_ground"
const ROAD: StringName = &"road"

func choose_route(candidates: Array) -> Dictionary:
	var best_route: Dictionary = {}
	var best_cost := INF
	for candidate_variant in candidates:
		if not candidate_variant is Dictionary:
			continue
		var candidate: Dictionary = candidate_variant
		var cost := route_cost(candidate)
		if cost < best_cost:
			best_cost = cost
			best_route = candidate
	return best_route

func route_cost(candidate: Dictionary) -> float:
	var segments: Array = candidate.get("segments", [])
	if segments.is_empty():
		return INF
	var total := 0.0
	for segment_variant in segments:
		if not segment_variant is Dictionary:
			return INF
		var segment: Dictionary = segment_variant
		if bool(segment.get("blocked", false)):
			return INF
		var length_m := maxf(0.0, float(segment.get("length_m", 0.0)))
		var surface := StringName(segment.get("surface", OPEN_GROUND))
		total += length_m * surface_weight(surface)
	return total

func surface_weight(surface: StringName) -> float:
	match surface:
		FOOTWAY, PEDESTRIAN, SIDEWALK, PLAZA:
			return 0.70
		CROSSING:
			return 0.85
		PATH:
			return 0.90
		OPEN_GROUND:
			return 1.20
		ROAD:
			return 3.00
		_:
			return 1.50
