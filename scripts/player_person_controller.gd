class_name PlayerPersonController
extends Node

## Converts player input into Person movement intent or generic driver-seat vehicle controls.
##
## Dependencies:
## - Parent must expose Person movement/occupancy APIs.
## - Driver control uses the occupied seat's public vehicle API; Person contains no driving logic.

const MovementIntentScript = preload("res://scripts/person_movement_intent.gd")
const InteractionQueryScript = preload("res://scripts/interaction_query.gd")
const PLAYER_VEHICLE_OWNER: int = 0

@export var person_path: NodePath = NodePath("..")

var person = null
var nearby_interactable = null

func _ready() -> void:
	person = get_node_or_null(person_path)

func _physics_process(_delta: float) -> void:
	if person == null:
		return
	if person.call("current_seat") != null:
		_apply_live_vehicle_controls()
		return
	var direction := Vector2(
		float(int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A))),
		float(int(Input.is_physical_key_pressed(KEY_S)) - int(Input.is_physical_key_pressed(KEY_W)))
	)
	apply_person_intent(direction, Input.is_physical_key_pressed(KEY_SHIFT))

func apply_person_intent(direction: Vector2, run: bool) -> void:
	if person == null or person.call("current_seat") != null:
		return
	person.call("apply_movement_intent", MovementIntentScript.new(direction, run))

func vehicle_control_target():
	if person == null:
		return null
	var seat = person.call("current_seat")
	if seat == null or not bool(seat.get("driver_capable")) or not seat.has_method("vehicle"):
		return null
	return seat.call("vehicle")

func apply_vehicle_controls(throttle: float, brake: float, steering: float) -> bool:
	var vehicle = vehicle_control_target()
	if vehicle == null:
		return false
	vehicle.call("set_control_owner", PLAYER_VEHICLE_OWNER)
	return bool(vehicle.call("set_control_inputs", PLAYER_VEHICLE_OWNER, throttle, brake, steering))

func set_nearby_interactable(interactable) -> void:
	nearby_interactable = interactable

func available_interactions() -> Array[StringName]:
	return InteractionQueryScript.available_actions(person, nearby_interactable)

func perform_interaction(action: StringName) -> bool:
	return InteractionQueryScript.perform(person, nearby_interactable, action)

func _apply_live_vehicle_controls() -> void:
	var throttle := float(int(Input.is_physical_key_pressed(KEY_W)) - int(Input.is_physical_key_pressed(KEY_S)))
	var steering := float(int(Input.is_physical_key_pressed(KEY_A)) - int(Input.is_physical_key_pressed(KEY_D)))
	var brake := 1.0 if Input.is_physical_key_pressed(KEY_SPACE) else 0.0
	apply_vehicle_controls(throttle, brake, steering)
