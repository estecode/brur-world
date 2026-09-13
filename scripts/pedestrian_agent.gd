class_name PedestrianAgent
extends RefCounted

## Stores lightweight pedestrian identity and meaningful state while no full Person is active.
##
## Dependencies:
## - Pure logical state with no SceneTree, rendering, physics, traffic, or player dependency.
## - Promotion/demotion is performed by PedestrianPopulation, not by this core state object.

var person_id: StringName = &""
var position: Vector3 = Vector3.ZERO
var facing_rad: float = 0.0
var destination: Vector3 = Vector3.ZERO
var route_index: int = 0
var waiting_for_vehicle: bool = false

func _init(new_person_id: StringName = &"", new_position: Vector3 = Vector3.ZERO) -> void:
	person_id = new_person_id
	position = new_position

func capture_person(person) -> void:
	if person == null:
		return
	person_id = StringName(person.get("person_id"))
	position = person.global_position
	facing_rad = person.rotation.y

func apply_to_person(person) -> void:
	if person == null:
		return
	person.set("person_id", person_id)
	person.global_position = position
	person.rotation.y = facing_rad
