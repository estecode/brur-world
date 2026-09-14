class_name PoliceLastKnownTargetState
extends RefCounted

## Owns the last explicitly observed on-foot target state without reading live player state.
##
## Dependencies:
## - Consumes PoliceObservationStore-shaped dictionaries and caller-provided time.
## - Owns no Person, SceneTree, routing, rendering, or sensor access.

var _latest: Dictionary = {}

func update_from_observation(observation: Dictionary) -> bool:
	if observation.is_empty():
		return false
	var position: Vector2 = observation.get("position", Vector2(INF, INF))
	if not position.is_finite():
		return false
	var timestamp_s := float(observation.get("timestamp_s", -INF))
	if not _latest.is_empty() and timestamp_s < float(_latest.get("timestamp_s", -INF)):
		return false
	_latest = {
		"position": position,
		"timestamp_s": timestamp_s,
		"heading_deg": fposmod(float(observation.get("heading_deg", 0.0)), 360.0),
		"speed_mps": maxf(0.0, float(observation.get("speed_mps", 0.0))),
		"confirmed": bool(observation.get("confirmed", true)),
		"source_unit_id": String(observation.get("source_unit_id", "")),
	}
	return true

func has_state() -> bool:
	return not _latest.is_empty()

func snapshot(now_s: float) -> Dictionary:
	if _latest.is_empty():
		return {}
	var result := _latest.duplicate(true)
	result["age_s"] = maxf(0.0, now_s - float(result["timestamp_s"]))
	result["confidence"] = 1.0 if bool(result.get("confirmed", true)) else 0.5
	return result

func clear() -> void:
	_latest.clear()
