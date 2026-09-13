class_name PoliceObservationStore
extends RefCounted

## Stores the latest explicitly published police observation of the player.
##
## Dependencies:
## - Uses only Godot value types and caller-provided observation data/time.
## - Does not read player, vehicle, routing, SceneTree, rendering, or sensor state.

const DEFAULT_STALE_AFTER_S: float = 10.0

var _stale_after_s: float = DEFAULT_STALE_AFTER_S
var _latest: Dictionary = {}

func _init(stale_after_s: float = DEFAULT_STALE_AFTER_S) -> void:
	_stale_after_s = maxf(stale_after_s, 0.0)

func publish(
		position: Vector2,
		timestamp_s: float,
		heading_deg: float,
		speed_mps: float,
		source_unit_id: String,
		confirmed: bool = true
) -> bool:
	var normalized_source := source_unit_id.strip_edges()
	if normalized_source.is_empty():
		return false
	if not _latest.is_empty() and timestamp_s < float(_latest["timestamp_s"]):
		return false

	_latest = {
		"position": position,
		"timestamp_s": timestamp_s,
		"heading_deg": fposmod(heading_deg, 360.0),
		"speed_mps": maxf(speed_mps, 0.0),
		"source_unit_id": normalized_source,
		"confirmed": confirmed,
	}
	return true

func has_observation() -> bool:
	return not _latest.is_empty()

func get_latest(now_s: float) -> Dictionary:
	if _latest.is_empty():
		return {}

	var result := _latest.duplicate(true)
	var age_s := get_age_s(now_s)
	var stale := age_s > _stale_after_s
	result["age_s"] = age_s
	result["stale"] = stale
	result["current"] = bool(result["confirmed"]) and not stale
	return result

func get_age_s(now_s: float) -> float:
	if _latest.is_empty():
		return INF
	return maxf(0.0, now_s - float(_latest["timestamp_s"]))

func clear() -> void:
	_latest.clear()
