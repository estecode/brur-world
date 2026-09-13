class_name PersonMovementIntent
extends RefCounted

## Carries role-agnostic movement intent into Person movement logic.
##
## Dependencies:
## - Pure data object; no SceneTree, input, navigation, vehicle, or rendering dependency.

var direction: Vector2 = Vector2.ZERO
var run: bool = false

func _init(new_direction: Vector2 = Vector2.ZERO, should_run: bool = false) -> void:
	direction = new_direction
	run = should_run

func normalized_direction() -> Vector2:
	if direction.length_squared() <= 1.0:
		return direction
	return direction.normalized()
