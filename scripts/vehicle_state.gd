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
var speed_mps: float = 0.0

func copy_from(other) -> void:
	x_m = other.x_m
	z_m = other.z_m
	heading_rad = other.heading_rad
	speed_mps = other.speed_mps

func duplicate_state():
	var result = get_script().new()
	result.copy_from(self)
	return result
