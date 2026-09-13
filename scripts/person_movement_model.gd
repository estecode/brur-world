class_name PersonMovementModel
extends RefCounted

## Owns deterministic role-independent on-foot movement state.
##
## Dependencies:
## - Consumes PersonMovementIntent-compatible data only.
## - Has no SceneTree, input, navigation, vehicle, rendering, or role dependency.

enum MovementState {
	STANDING,
	WALKING,
	RUNNING,
	FALLING,
}

const ROAD: StringName = &"road"
const OPEN_GROUND: StringName = &"open_ground"
const FOOTWAY: StringName = &"footway"
const PARKING: StringName = &"parking"
const BUILDING: StringName = &"building"
const WALL: StringName = &"wall"
const FENCE: StringName = &"fence"
const WATER: StringName = &"water"

var walk_speed_mps: float = 1.8
var run_speed_mps: float = 5.2
var acceleration_mps2: float = 12.0
var deceleration_mps2: float = 16.0
var velocity_xz: Vector2 = Vector2.ZERO
var facing_rad: float = 0.0
var movement_state: MovementState = MovementState.STANDING

func step(intent, delta: float, blocked: bool = false, falling: bool = false) -> Vector2:
	if falling:
		movement_state = MovementState.FALLING
		velocity_xz = velocity_xz.move_toward(Vector2.ZERO, deceleration_mps2 * maxf(delta, 0.0))
		return velocity_xz

	var direction: Vector2 = Vector2.ZERO
	var should_run := false
	if intent != null:
		direction = intent.call("normalized_direction")
		should_run = bool(intent.get("run"))

	if blocked:
		direction = Vector2.ZERO

	var target_speed := run_speed_mps if should_run else walk_speed_mps
	var target_velocity := direction * target_speed
	var rate := acceleration_mps2 if not direction.is_zero_approx() else deceleration_mps2
	velocity_xz = velocity_xz.move_toward(target_velocity, rate * maxf(delta, 0.0))

	if not direction.is_zero_approx():
		facing_rad = atan2(direction.x, -direction.y)

	if velocity_xz.length() < 0.01:
		movement_state = MovementState.STANDING
	elif should_run:
		movement_state = MovementState.RUNNING
	else:
		movement_state = MovementState.WALKING
	return velocity_xz

func can_traverse_surface(surface_kind: StringName) -> bool:
	return surface_kind not in [BUILDING, WALL, FENCE, WATER]
