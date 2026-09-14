class_name PoliceFootSearchArea
extends RefCounted

## Derives a deterministic local search area from last-known target state and traversability.
##
## Dependencies:
## - Consumes PoliceLastKnownTargetState-shaped dictionaries.
## - Optionally calls an injected local-space API exposing is_traversable(Vector2).
## - Does not depend on pedestrian paths, SceneTree, player transforms, routing internals, or rendering.

var plausible_speed_mps: float = 4.5
var base_radius_m: float = 4.0
var max_radius_m: float = 140.0

func derive(last_known: Dictionary, now_s: float, local_space = null) -> Dictionary:
	if last_known.is_empty():
		return {}
	var center: Vector2 = last_known.get("position", Vector2(INF, INF))
	if not center.is_finite():
		return {}
	var timestamp_s := float(last_known.get("timestamp_s", now_s))
	var age_s := maxf(0.0, now_s - timestamp_s)
	var radius_m := clampf(base_radius_m + age_s * plausible_speed_mps, base_radius_m, max_radius_m)
	var candidates: Array[Vector2] = []
	var offsets := [
		Vector2.ZERO,
		Vector2(radius_m, 0.0), Vector2(-radius_m, 0.0),
		Vector2(0.0, radius_m), Vector2(0.0, -radius_m),
		Vector2(radius_m, radius_m) * 0.70710678,
		Vector2(radius_m, -radius_m) * 0.70710678,
		Vector2(-radius_m, radius_m) * 0.70710678,
		Vector2(-radius_m, -radius_m) * 0.70710678,
	]
	for offset in offsets:
		var candidate: Vector2 = center + offset
		if local_space != null and local_space.has_method("is_traversable") and not bool(local_space.call("is_traversable", candidate)):
			continue
		candidates.append(candidate)
	return {
		"center": center,
		"radius_m": radius_m,
		"age_s": age_s,
		"candidates": candidates,
		"source_timestamp_s": timestamp_s,
		"confidence": float(last_known.get("confidence", 1.0)),
	}
