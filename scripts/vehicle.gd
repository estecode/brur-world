extends Node3D
class_name Vehicle

## Shared runtime object for anything that moves as a vehicle.
##
## Dependencies:
## - Has no dependency on player input, traffic AI, police AI, routing, or rendering.
## - Controllers provide throttle/brake/steering commands through set_control_inputs().
## - Owns common vehicle data and simple flat-world motion integration.

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

var speed_mps: float = 0.0
var target_speed_mps: float = 0.0
var steering: float = 0.0
var throttle_input: float = 0.0
var brake_input: float = 0.0
var active: bool = true
var emergency_lights_active: bool = false

func _physics_process(delta: float) -> void:
	if not active:
		return
	_integrate_speed(delta)
	_integrate_heading(delta)
	_integrate_position(delta)

func configure(new_kind: Kind) -> void:
	kind = new_kind
	_apply_default_profile()

func set_control_inputs(throttle: float, brake: float, new_steering: float) -> void:
	throttle_input = clampf(throttle, -1.0, 1.0)
	brake_input = clampf(brake, 0.0, 1.0)
	steering = clampf(new_steering, -1.0, 1.0)

func clear_control_inputs() -> void:
	set_control_inputs(0.0, 0.0, 0.0)

func set_target_speed(new_target_mps: float) -> void:
	target_speed_mps = clampf(new_target_mps, -max_reverse_speed_mps, max_speed_mps)

func set_motion_state(new_speed_mps: float, new_steering: float = 0.0) -> void:
	speed_mps = clampf(new_speed_mps, -max_reverse_speed_mps, max_speed_mps)
	steering = clampf(new_steering, -1.0, 1.0)

func stop() -> void:
	target_speed_mps = 0.0
	speed_mps = 0.0
	clear_control_inputs()

func is_emergency_vehicle() -> bool:
	return kind in [Kind.POLICE_CAR, Kind.FIRE_ENGINE, Kind.AMBULANCE]

func speed_kmh() -> float:
	return speed_mps * 3.6

func _integrate_speed(delta: float) -> void:
	if brake_input > 0.0:
		speed_mps = move_toward(speed_mps, 0.0, braking_mps2 * brake_input * delta)
		return
	if throttle_input > 0.0:
		speed_mps = minf(max_speed_mps, speed_mps + acceleration_mps2 * throttle_input * delta)
	elif throttle_input < 0.0:
		if speed_mps > 0.0:
			speed_mps = move_toward(speed_mps, 0.0, braking_mps2 * -throttle_input * delta)
		else:
			speed_mps = maxf(-max_reverse_speed_mps, speed_mps - acceleration_mps2 * -throttle_input * delta)

func _integrate_heading(delta: float) -> void:
	if absf(speed_mps) < 0.05 or absf(steering) < 0.001:
		return
	var wheelbase_m: float = maxf(length_m * 0.6, 0.8)
	var steer_angle: float = deg_to_rad(max_steer_degrees) * steering
	var yaw_rate: float = speed_mps / wheelbase_m * tan(steer_angle)
	rotate_y(yaw_rate * delta)

func _integrate_position(delta: float) -> void:
	if absf(speed_mps) < 0.001:
		return
	var forward: Vector3 = -global_transform.basis.z.normalized()
	global_position += forward * speed_mps * delta

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
