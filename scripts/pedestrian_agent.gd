class_name PedestrianAgent
extends RefCounted

## Stores lightweight pedestrian identity and meaningful state while no full Person is active.
##
## Dependencies:
## - Reuses PersonMovementModel for deterministic lightweight motion without SceneTree physics.
## - Promotion/demotion is performed by PedestrianPopulation, not by this core state object.

const MovementModelScript = preload("res://scripts/person_movement_model.gd")

var person_id: StringName = &""
var position: Vector3 = Vector3.ZERO
var facing_rad: float = 0.0
var destination: Vector3 = Vector3.ZERO
var route_index: int = 0
var waiting_for_vehicle: bool = false
var movement_model = MovementModelScript.new()

func _init(new_person_id: StringName = &"", new_position: Vector3 = Vector3.ZERO) -> void:
	person_id = new_person_id
	position = new_position

func advance(intent, delta: float) -> void:
	var planar_velocity: Vector2 = movement_model.step(intent, delta)
	position += Vector3(planar_velocity.x, 0.0, planar_velocity.y) * maxf(delta, 0.0)
	facing_rad = movement_model.facing_rad

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
