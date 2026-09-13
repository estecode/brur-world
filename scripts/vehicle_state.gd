class_name VehicleState
extends RefCounted

## Stores deterministic vehicle simulation state in real-world units.
##
## Dependencies:
## - Has no SceneTree, rendering, input, routing, traffic, or police dependency.
## - VehicleDynamics mutates this state; Godot adapters only present it.

var x_m: float = 0.0
var z_m: float = 0.0
var heading_rad: float = 0.0
var travel_heading_rad: float = 0.0
var travel_heading_initialized: bool = false
var speed_mps: float = 0.0
var yaw_rate_rps: float = 0.0

var energy_type: StringName = &""
var energy_capacity: float = 0.0
var energy_remaining: float = 0.0
var tire_condition: float = 1.0

var last_longitudinal_accel_mps2: float = 0.0
var last_lateral_accel_mps2: float = 0.0
var last_grip_usage: float = 0.0
var last_slip_angle_rad: float = 0.0

func copy_from(other) -> void:
	x_m = other.x_m
	z_m = other.z_m
	heading_rad = other.heading_rad
	travel_heading_rad = other.travel_heading_rad
	travel_heading_initialized = other.travel_heading_initialized
	speed_mps = other.speed_mps
	yaw_rate_rps = other.yaw_rate_rps
	energy_type = other.energy_type
	energy_capacity = other.energy_capacity
	energy_remaining = other.energy_remaining
	tire_condition = other.tire_condition
	last_longitudinal_accel_mps2 = other.last_longitudinal_accel_mps2
	last_lateral_accel_mps2 = other.last_lateral_accel_mps2
	last_grip_usage = other.last_grip_usage
	last_slip_angle_rad = other.last_slip_angle_rad

func duplicate_state():
	var result = get_script().new()
	result.copy_from(self)
	return result
