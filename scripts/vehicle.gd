extends Node3D
class_name Vehicle

## Adapts portable vehicle state/dynamics to a Godot Node3D vehicle instance.
##
## Dependencies:
## - Owns VehicleState and delegates deterministic motion to VehicleDynamics.
## - Accepts generic controls from exactly one explicit control owner at a time.
## - Has no dependency on player input, GPS routing policy, traffic AI, police AI, or camera code.

const VehicleStateScript = preload("res://scripts/vehicle_state.gd")
const VehicleDynamicsScript = preload("res://scripts/vehicle_dynamics.gd")

enum Kind {
	CAR,
	POLICE_CAR,
	FIRE_ENGINE,
	AMBULANCE,
	TRUCK,
	MOTORCYCLE,
	MOPED,
	BICYCLE,
	E_SCOOTER,
}

enum ControlOwner {
	PLAYER,
	GPS,
}

@export var kind: Kind = Kind.CAR
@export var vehicle_id: StringName = &""
@export var length_m: float = 4.5
@export var width_m: float = 1.8
@export var height_m: float = 1.5
@export var max_speed_mps: float = 36.1
@export var acceleration_mps2: float = 3.0
@export var braking_mps2: float = 7.0
@export var max_reverse_speed_mps: float = 5.0
@export var max_steer_degrees: float = 32.0
@export var active: bool = true

var emergency_lights_active: bool = false

var _state: VehicleState = VehicleStateScript.new()
var _state_initialized: bool = false
var _control_owner: ControlOwner = ControlOwner.PLAYER
var _throttle_input: float = 0.0
var _brake_input: float = 0.0
var _steering_input: float = 0.0

func _physics_process(delta: float) -> void:
	if not active:
		return
	_ensure_state_from_transform()
	VehicleDynamicsScript.step(
		_state,
		_throttle_input,
		_brake_input,
		_steering_input,
		delta,
		length_m,
		max_speed_mps,
		acceleration_mps2,
		braking_mps2,
		max_reverse_speed_mps,
		max_steer_degrees
	)
	_apply_state_to_transform()

func configure(new_kind: Kind) -> void:
	kind = new_kind
	_apply_default_profile()

func set_control_owner(owner: ControlOwner) -> void:
	if _control_owner == owner:
		return
	_control_owner = owner
	_clear_inputs_unchecked()

func control_owner() -> ControlOwner:
	return _control_owner

func set_control_inputs(owner: ControlOwner, throttle: float, brake: float, steering: float) -> bool:
	if owner != _control_owner:
		return false
	_throttle_input = clampf(throttle, -1.0, 1.0)
	_brake_input = clampf(brake, 0.0, 1.0)
	_steering_input = clampf(steering, -1.0, 1.0)
	return true

func clear_control_inputs(owner: ControlOwner) -> bool:
	if owner != _control_owner:
		return false
	_clear_inputs_unchecked()
	return true

func set_world_position(new_position: Vector3) -> void:
	_state.x_m = new_position.x
	_state.z_m = new_position.z
	_state_initialized = true
	global_position = Vector3(new_position.x, new_position.y, new_position.z)

func set_heading_rad(new_heading_rad: float) -> void:
	_state.heading_rad = wrapf(new_heading_rad, -PI, PI)
	_state_initialized = true
	rotation.y = _state.heading_rad

func set_motion_state(new_speed_mps: float, new_heading_rad: float = NAN) -> void:
	_ensure_state_from_transform()
	_state.speed_mps = clampf(new_speed_mps, -max_reverse_speed_mps, max_speed_mps)
	if not is_nan(new_heading_rad):
		_state.heading_rad = wrapf(new_heading_rad, -PI, PI)
	_apply_state_to_transform()

func stop() -> void:
	_ensure_state_from_transform()
	_state.speed_mps = 0.0
	_clear_inputs_unchecked()

func speed_mps() -> float:
	return _state.speed_mps

func speed_kmh() -> float:
	return _state.speed_mps * 3.6

func heading_rad() -> float:
	return _state.heading_rad

func state_snapshot() -> VehicleState:
	_ensure_state_from_transform()
	return _state.duplicate_state()

func is_emergency_vehicle() -> bool:
	return kind in [Kind.POLICE_CAR, Kind.FIRE_ENGINE, Kind.AMBULANCE]

func _ensure_state_from_transform() -> void:
	if _state_initialized:
		return
	_state.x_m = global_position.x
	_state.z_m = global_position.z
	_state.heading_rad = rotation.y
	_state_initialized = true

func _apply_state_to_transform() -> void:
	global_position.x = _state.x_m
	global_position.z = _state.z_m
	rotation.y = _state.heading_rad

func _clear_inputs_unchecked() -> void:
	_throttle_input = 0.0
	_brake_input = 0.0
	_steering_input = 0.0

func _apply_default_profile() -> void:
	match kind:
		Kind.CAR:
			_set_profile(4.5, 1.8, 1.5, 36.1, 3.0, 7.0)
		Kind.POLICE_CAR:
			_set_profile(4.8, 1.9, 1.5, 55.6, 4.5, 9.0)
		Kind.FIRE_ENGINE:
			_set_profile(8.5, 2.5, 3.2, 27.8, 1.5, 6.0)
		Kind.AMBULANCE:
			_set_profile(6.0, 2.1, 2.7, 44.4, 2.8, 7.5)
		Kind.TRUCK:
			_set_profile(12.0, 2.5, 3.8, 25.0, 1.0, 5.0)
		Kind.MOTORCYCLE:
			_set_profile(2.2, 0.8, 1.3, 50.0, 5.0, 9.0)
		Kind.MOPED:
			_set_profile(1.9, 0.7, 1.2, 12.5, 2.5, 6.0)
		Kind.BICYCLE:
			_set_profile(1.8, 0.65, 1.2, 12.0, 1.5, 4.0)
		Kind.E_SCOOTER:
			_set_profile(1.2, 0.55, 1.2, 7.0, 2.0, 4.0)

func _set_profile(
	new_length_m: float,
	new_width_m: float,
	new_height_m: float,
	new_max_speed_mps: float,
	new_acceleration_mps2: float,
	new_braking_mps2: float
) -> void:
	length_m = new_length_m
	width_m = new_width_m
	height_m = new_height_m
	max_speed_mps = new_max_speed_mps
	acceleration_mps2 = new_acceleration_mps2
	braking_mps2 = new_braking_mps2
