class_name RouteDrivingProfile
extends RefCounted

## Holds immutable-style tuning values for one AI route-driving mode.
##
## Dependencies:
## - Pure driving-policy data only; no SceneTree, vehicle, routing, GPS, traffic, or rendering dependency.

var speed_limit_multiplier: float
var max_lateral_accel_mps2: float
var comfort_brake_mps2: float
var throttle_error_scale_mps: float
var brake_error_scale_mps: float
var minimum_throttle: float
var minimum_brake: float
var throttle_cap: float
var brake_cap: float
var intersection_speed_factor: float
var intersection_gap_factor: float

func _init(
	new_speed_limit_multiplier: float,
	new_max_lateral_accel_mps2: float,
	new_comfort_brake_mps2: float,
	new_throttle_error_scale_mps: float,
	new_brake_error_scale_mps: float,
	new_minimum_throttle: float,
	new_minimum_brake: float,
	new_throttle_cap: float,
	new_brake_cap: float,
	new_intersection_speed_factor: float,
	new_intersection_gap_factor: float
) -> void:
	speed_limit_multiplier = new_speed_limit_multiplier
	max_lateral_accel_mps2 = new_max_lateral_accel_mps2
	comfort_brake_mps2 = new_comfort_brake_mps2
	throttle_error_scale_mps = new_throttle_error_scale_mps
	brake_error_scale_mps = new_brake_error_scale_mps
	minimum_throttle = new_minimum_throttle
	minimum_brake = new_minimum_brake
	throttle_cap = new_throttle_cap
	brake_cap = new_brake_cap
	intersection_speed_factor = new_intersection_speed_factor
	intersection_gap_factor = new_intersection_gap_factor
