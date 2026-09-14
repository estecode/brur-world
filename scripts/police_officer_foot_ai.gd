class_name PoliceOfficerFootAI
extends RefCounted

## Converts shared police observations into chase/search movement intent for a generic Person.
##
## Dependencies:
## - Reads only PoliceObservationStore public snapshots plus injected local traversability.
## - Uses PoliceLastKnownTargetState, PoliceFootSearchArea, PoliceFootSearchTask and PersonMovementIntent.
## - Never reads the player's live transform, Person internals, routing graph, SceneTree, or rendering.

const LastKnownScript = preload("res://scripts/police_last_known_target_state.gd")
const SearchAreaScript = preload("res://scripts/police_foot_search_area.gd")
const SearchTaskScript = preload("res://scripts/police_foot_search_task.gd")
const MovementIntentScript = preload("res://scripts/person_movement_intent.gd")

var observation_store
var last_known = LastKnownScript.new()
var search_area = SearchAreaScript.new()
var search_task = SearchTaskScript.new()

func setup(shared_observation_store) -> bool:
	observation_store = shared_observation_store
	return observation_store != null and observation_store.has_method("get_latest")

func plan(now_s: float, officer_position: Vector2, local_space = null) -> Dictionary:
	if observation_store == null or not officer_position.is_finite():
		return _idle_plan()
	var observation: Dictionary = observation_store.call("get_latest", now_s)
	if not observation.is_empty():
		last_known.update_from_observation(observation)
		if bool(observation.get("current", false)):
			return _movement_plan(&"pursue", officer_position, observation.get("position", Vector2(INF, INF)), true, observation)
	if not last_known.has_state():
		return _idle_plan()
	var known := last_known.snapshot(now_s)
	var area := search_area.derive(known, now_s, local_space)
	var task := search_task.choose(area, officer_position)
	if task.is_empty():
		return _movement_plan(&"search_last_known", officer_position, known.get("position", Vector2(INF, INF)), true, known)
	return _movement_plan(&"search", officer_position, task.get("target_position", Vector2(INF, INF)), true, task)

func _movement_plan(mode: StringName, officer_position: Vector2, target: Vector2, run: bool, source: Dictionary) -> Dictionary:
	if not target.is_finite():
		return _idle_plan()
	var offset := target - officer_position
	var direction := offset.normalized() if offset.length_squared() > 0.0001 else Vector2.ZERO
	return {
		"mode": mode,
		"target_position": target,
		"intent": MovementIntentScript.new(direction, run),
		"source_timestamp_s": float(source.get("source_timestamp_s", source.get("timestamp_s", 0.0))),
		"confidence": float(source.get("confidence", 1.0 if bool(source.get("confirmed", true)) else 0.5)),
	}

func _idle_plan() -> Dictionary:
	return {"mode": &"idle", "intent": MovementIntentScript.new()}
