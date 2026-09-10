extends RefCounted
class_name WorldStreamRequest

## Carries one immutable snapshot of camera-driven world streaming demand.
##
## Dependencies:
## - Uses only Godot value types.
## - Contains no rendering, SceneTree, file I/O, routing, or layer-specific policy.

var focus_world: Vector3
var altitude_m: float
var motion_world: Vector3

func _init(focus: Vector3, altitude: float, motion: Vector3 = Vector3.ZERO) -> void:
	focus_world = focus
	altitude_m = altitude
	motion_world = motion

func horizontal_motion() -> Vector2:
	return Vector2(motion_world.x, motion_world.z)
