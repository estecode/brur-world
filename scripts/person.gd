class_name Person
extends CharacterBody3D

## Adapts generic person movement/occupancy state to Godot CharacterBody3D physics.
##
## Dependencies:
## - Owns PersonMovementModel state and accepts external PersonMovementIntent.
## - Uses Godot collision only as a physical adapter; no input, navigation, AI, role, or vehicle-driving policy.

signal collision_event(collider)

const MovementModelScript = preload("res://scripts/person_movement_model.gd")
const MovementIntentScript = preload("res://scripts/person_movement_intent.gd")

@export var person_id: StringName = &"person"
@export var gravity_mps2: float = 9.8

var _movement_model = MovementModelScript.new()
var _movement_intent = MovementIntentScript.new()
var _occupied_seat = null
var _saved_collision_layer: int = 1
var _saved_collision_mask: int = 1

func _physics_process(delta: float) -> void:
	if _occupied_seat != null:
		velocity = Vector3.ZERO
		if is_instance_valid(_occupied_seat) and _occupied_seat is Node3D:
			global_position = (_occupied_seat as Node3D).global_position
		return

	var falling := not is_on_floor() and not is_zero_approx(gravity_mps2)
	var planar_velocity: Vector2 = _movement_model.step(_movement_intent, delta, false, falling)
	velocity.x = planar_velocity.x
	velocity.z = planar_velocity.y
	if is_on_floor():
		velocity.y = 0.0
	elif gravity_mps2 > 0.0:
		velocity.y -= gravity_mps2 * delta
	rotation.y = _movement_model.facing_rad
	move_and_slide()
	for index in get_slide_collision_count():
		var collision := get_slide_collision(index)
		if collision != null:
			collision_event.emit(collision.get_collider())

func apply_movement_intent(intent) -> void:
	if _occupied_seat != null:
		return
	_movement_intent = intent if intent != null else MovementIntentScript.new()

func movement_state() -> int:
	return _movement_model.movement_state

func movement_model():
	return _movement_model

func current_seat():
	return _occupied_seat

func occupy_seat(seat) -> bool:
	if seat == null or _occupied_seat != null:
		return false
	_occupied_seat = seat
	_saved_collision_layer = collision_layer
	_saved_collision_mask = collision_mask
	collision_layer = 0
	collision_mask = 0
	visible = false
	velocity = Vector3.ZERO
	return true

func leave_seat(seat, exit_position: Vector3) -> bool:
	if seat == null or _occupied_seat != seat:
		return false
	_occupied_seat = null
	collision_layer = _saved_collision_layer
	collision_mask = _saved_collision_mask
	global_position = exit_position
	visible = true
	velocity = Vector3.ZERO
	_movement_intent = MovementIntentScript.new()
	return true
