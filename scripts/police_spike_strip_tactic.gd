class_name PoliceSpikeStripTactic
extends RefCounted

## Models an abstract, game-focused spike-strip tactic lifecycle at a routing-supplied target.
##
## Dependencies:
## - Consumes shared police observations and an injected routing owner for an abstract point ahead.
## - Uses PoliceTacticReservationStore for coordination.
## - Does not encode real deployment geometry, timing, police procedure or Vehicle physics.

enum State { IDLE, REQUESTED, PREPARING, ACTIVE, FINISHED, CANCELLED }

const TACTIC_ID: StringName = &"spike_strip"

var state: int = State.IDLE
var unit_id: StringName = &""
var target_position: Vector2 = Vector2(INF, INF)
var source_timestamp_s: float = -1.0
var prepare_elapsed_s: float = 0.0
var active_elapsed_s: float = 0.0
var prepare_duration_s: float = 1.0
var active_duration_s: float = 8.0
var abstract_lead_distance_m: float = 90.0
var _routing_owner
var _reservations

func tactic_id() -> StringName:
	return TACTIC_ID

func setup(new_unit_id: StringName, routing_owner, reservation_store) -> bool:
	unit_id = new_unit_id
	_routing_owner = routing_owner
	_reservations = reservation_store
	return unit_id != &"" and _routing_owner != null and _routing_owner.has_method("advance_along_road") and _reservations != null

func request(observation: Dictionary) -> Dictionary:
	if state != State.IDLE and state != State.FINISHED and state != State.CANCELLED:
		return {}
	if observation.is_empty() or bool(observation.get("stale", false)) or not bool(observation.get("current", false)):
		return {}
	var observed_position: Vector2 = observation.get("position", Vector2(INF, INF))
	if not observed_position.is_finite():
		return {}
	var heading_deg := float(observation.get("heading_deg", 0.0))
	var candidate_value: Variant = _routing_owner.call("advance_along_road", observed_position, heading_deg, abstract_lead_distance_m)
	if not candidate_value is Vector2:
		return {}
	var candidate := candidate_value as Vector2
	if not candidate.is_finite() or not bool(_reservations.call("try_reserve", unit_id, TACTIC_ID, candidate)):
		return {}
	target_position = candidate
	source_timestamp_s = float(observation.get("timestamp_s", 0.0))
	prepare_elapsed_s = 0.0
	active_elapsed_s = 0.0
	state = State.REQUESTED
	return snapshot()

func step(delta: float, unit_position: Vector2) -> void:
	var dt := maxf(delta, 0.0)
	if state == State.REQUESTED:
		state = State.PREPARING
	elif state == State.PREPARING:
		prepare_elapsed_s += dt
		if unit_position.is_finite() and target_position.is_finite() and unit_position.distance_to(target_position) <= 8.0 and prepare_elapsed_s >= prepare_duration_s:
			state = State.ACTIVE
	elif state == State.ACTIVE:
		active_elapsed_s += dt
		if active_elapsed_s >= active_duration_s:
			finish()

func should_replan(observation: Dictionary) -> bool:
	if state == State.IDLE or state == State.FINISHED or state == State.CANCELLED or observation.is_empty():
		return false
	var timestamp_s := float(observation.get("timestamp_s", source_timestamp_s))
	if timestamp_s <= source_timestamp_s:
		return false
	var observed_position: Vector2 = observation.get("position", Vector2(INF, INF))
	return observed_position.is_finite() and target_position.is_finite() and observed_position.distance_to(target_position) > 35.0

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
	return {
		"tactic_id": TACTIC_ID,
		"unit_id": unit_id,
		"state": state,
		"state_name": str(State.keys()[state]),
		"target_position": target_position,
		"source_timestamp_s": source_timestamp_s,
	}
