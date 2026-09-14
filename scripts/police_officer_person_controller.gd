class_name PoliceOfficerPersonController
extends Node

## Applies non-omniscient police foot-AI movement intent to a generic production Person.
##
## Dependencies:
## - PoliceOfficerFootAI produces role-specific movement intent from shared observations.
## - Person remains the generic physical movement owner.
## - Does not read player transforms, observation-store internals, routing internals, or rendering.

var person
var foot_ai
var local_space

func setup(person_node, police_foot_ai, search_local_space = null) -> bool:
	person = person_node
	foot_ai = police_foot_ai
	local_space = search_local_space
	return person != null and person.has_method("apply_movement_intent") and foot_ai != null and foot_ai.has_method("plan")

func update(now_s: float) -> Dictionary:
	if person == null or foot_ai == null:
		return {}
	var position := Vector2(float(person.global_position.x), float(person.global_position.z))
	var plan: Dictionary = foot_ai.call("plan", now_s, position, local_space)
	var intent = plan.get("intent", null)
	person.call("apply_movement_intent", intent)
	return plan
