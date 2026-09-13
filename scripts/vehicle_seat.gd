class_name VehicleSeat
extends Node3D

## Owns generic vehicle-seat occupancy and exposes enter/exit actions.
##
## Dependencies:
## - Lives below a vehicle exposing the public control API.
## - Talks to Person only through generic occupancy methods.
## - Has no player, AI, routing, or vehicle-driving policy dependency.

@export var driver_capable: bool = false
@export var compatible: bool = true
@export var exit_offset: Vector3 = Vector3(1.2, 0.0, 0.0)

var occupant = null

func available_actions(person) -> Array[StringName]:
	if person == null:
		return []
	if occupant == person:
		return [&"exit"]
	if not compatible or occupant != null:
		return []
	if person.has_method("current_seat") and person.call("current_seat") != null:
		return []
	return [&"enter"]

func perform_action(person, action: StringName) -> bool:
	match action:
		&"enter":
			return try_enter(person)
		&"exit":
			return try_exit(person)
	return false

func try_enter(person) -> bool:
	if person == null or not compatible or occupant != null:
		return false
	if not person.has_method("occupy_seat") or not person.has_method("current_seat"):
		return false
	if person.call("current_seat") != null:
		return false
	occupant = person
	if not bool(person.call("occupy_seat", self)):
		occupant = null
		return false
	return true

func try_exit(person) -> bool:
	if person == null or occupant != person or not person.has_method("leave_seat"):
		return false
	if not bool(person.call("leave_seat", self, exit_world_position())):
		return false
	occupant = null
	return true

func vehicle():
	var candidate: Node = get_parent()
	while candidate != null:
		if candidate.has_method("set_control_inputs"):
			return candidate
		candidate = candidate.get_parent()
	return null

func exit_world_position() -> Vector3:
	return global_transform * exit_offset
