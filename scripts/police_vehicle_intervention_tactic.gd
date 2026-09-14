class_name PoliceVehicleInterventionTactic
extends RefCounted

## Models permission and lifecycle for an abstract vehicle-intervention intent.
##
## Dependencies:
## - Consumes shared police observations plus caller-provided geometry suitability.
## - Emits only an abstract driver intent; it never calls Vehicle or low-level driving APIs.
## - Uses PoliceTacticReservationStore so only one unit claims the same intervention action.

enum State { IDLE, REQUESTED, PREPARING, ACTIVE, FINISHED, CANCELLED }

const TACTIC_ID: StringName = &"vehicle_intervention"

var state: int = State.IDLE
var unit_id: StringName = &""
var target_position: Vector2 = Vector2(INF, INF)
var source_timestamp_s: float = -1.0
var intervention_allowed: bool = false
var _reservations

func tactic_id() -> StringName:
	return TACTIC_ID

func setup(new_unit_id: StringName, reservation_store) -> bool:
	unit_id = new_unit_id
	_reservations = reservation_store
	return unit_id != &"" and _reservations != null

func set_intervention_allowed(allowed: bool) -> void:
	intervention_allowed = allowed

func request(observation: Dictionary) -> Dictionary:
	if state != State.IDLE and state != State.FINISHED and state != State.CANCELLED:
		return {}
	if not intervention_allowed or observation.is_empty() or bool(observation.get("stale", false)) or not bool(observation.get("current", false)):
		return {}
	var observed_position: Vector2 = observation.get("position", Vector2(INF, INF))
	if not observed_position.is_finite() or not bool(_reservations.call("try_reserve", unit_id, TACTIC_ID, observed_position)):
		return {}
	target_position = observed_position
	source_timestamp_s = float(observation.get("timestamp_s", 0.0))
	state = State.REQUESTED
	return snapshot()

func step(_delta: float, _unit_position: Vector2) -> void:
	if state == State.REQUESTED:
		state = State.PREPARING
	elif state == State.PREPARING:
		state = State.ACTIVE

func driver_intent() -> Dictionary:
	if state != State.ACTIVE or not intervention_allowed or not target_position.is_finite():
		return {}
	return {"intent": &"vehicle_intervention", "permitted": true, "target_position": target_position, "source_timestamp_s": source_timestamp_s}

func should_replan(observation: Dictionary) -> bool:
	if state == State.IDLE or is_terminal():
		return false
	if not intervention_allowed or observation.is_empty() or bool(observation.get("stale", false)) or not bool(observation.get("current", false)):
		return true
	var timestamp_s := float(observation.get("timestamp_s", source_timestamp_s))
	if timestamp_s <= source_timestamp_s:
		return false
	var observed_position: Vector2 = observation.get("position", Vector2(INF, INF))
	return not observed_position.is_finite() or observed_position.distance_to(target_position) > 25.0

func cancel() -> void:
	if unit_id != &"" and _reservations != null:
		_reservations.call("release", unit_id)
	state = State.CANCELLED

func finish() -> void:
	if unit_id != &"" and _reservations != null:
		_reservations.call("release", unit_id)
	state = State.FINISHED

func is_terminal() -> bool:
	return state == State.FINISHED or state == State.CANCELLED

func snapshot() -> Dictionary:
	return {"tactic_id": TACTIC_ID, "unit_id": unit_id, "state": state, "state_name": str(State.keys()[state]), "target_position": target_position, "source_timestamp_s": source_timestamp_s, "intervention_allowed": intervention_allowed}
