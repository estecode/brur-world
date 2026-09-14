class_name SpeedingOffenceDetector
extends RefCounted

## Detects clear speeding from an explicitly observed speed and the authoritative road limit.
##
## Dependencies:
## - Pure offence policy; no SceneTree, player, police vehicle, routing or observation-store dependency.

const DETECTOR_ID := &"speeding"
var clear_excess_kmh: float = 3.0

func detector_id() -> StringName:
	return DETECTOR_ID

func evaluate(observation: Dictionary, road_speed_limit_kmh: float) -> Dictionary:
	if observation.is_empty() or not bool(observation.get("current", false)):
		return {}
	if road_speed_limit_kmh <= 0.0:
		return {}
	var observed_kmh := maxf(0.0, float(observation.get("speed_mps", 0.0)) * 3.6)
	var excess_kmh := observed_kmh - road_speed_limit_kmh
	if excess_kmh <= clear_excess_kmh:
		return {}
	return {
		"type": DETECTOR_ID,
		"observed_speed_kmh": observed_kmh,
		"road_speed_limit_kmh": road_speed_limit_kmh,
		"excess_kmh": excess_kmh,
		"source_unit_id": str(observation.get("source_unit_id", "")),
		"timestamp_s": float(observation.get("timestamp_s", 0.0)),
	}
