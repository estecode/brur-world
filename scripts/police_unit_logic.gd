class_name PoliceUnitLogic
extends RefCounted

## Owns police patrol/observation/stop-attempt state transitions and detector composition.
##
## Dependencies:
## - Consumes caller-provided observations and road limits.
## - Offence detectors are independent small policy objects exposing detector_id/evaluate.
## - Does not own Vehicle physics, routing implementation, pursuit tactics or SceneTree state.

enum State { PATROL, OBSERVE, STOP_ATTEMPT, PURSUIT_HANDOFF }

var state: int = State.PATROL
var detectors: Array = []
var active_offence: Dictionary = {}
var stop_attempt_elapsed_s := 0.0
var pursuit_handoff_after_s := 6.0

func add_detector(detector) -> void:
	if detector != null and detector.has_method("evaluate") and detector.has_method("detector_id"):
		detectors.append(detector)

func update_from_observation(observation: Dictionary, road_speed_limit_kmh: float) -> Dictionary:
	if observation.is_empty() or not bool(observation.get("current", false)):
		if state == State.OBSERVE: state = State.PATROL
		return {}
	if state == State.PATROL: state = State.OBSERVE
	for detector in detectors:
		var offence: Dictionary = detector.call("evaluate", observation, road_speed_limit_kmh)
		if offence.is_empty(): continue
		active_offence = offence.duplicate(true)
		state = State.STOP_ATTEMPT
		stop_attempt_elapsed_s = 0.0
		return active_offence.duplicate(true)
	return {}

func step(delta: float, target_complied: bool = false) -> void:
	if state != State.STOP_ATTEMPT: return
	if target_complied:
		state = State.OBSERVE
		stop_attempt_elapsed_s = 0.0
		return
	stop_attempt_elapsed_s += maxf(0.0, delta)
	if stop_attempt_elapsed_s >= pursuit_handoff_after_s:
		state = State.PURSUIT_HANDOFF

func consume_pursuit_handoff() -> Dictionary:
	if state != State.PURSUIT_HANDOFF: return {}
	var result := {"offence": active_offence.duplicate(true)}
	state = State.OBSERVE
	stop_attempt_elapsed_s = 0.0
	return result

func state_name() -> String:
	return State.keys()[state]
