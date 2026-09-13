class_name PedestrianAI
extends RefCounted

## Converts pedestrian route preference and nearby danger into generic Person movement intent.
##
## Dependencies:
## - Uses PedestrianRoutePolicy to rank externally supplied routes.
## - Produces PersonMovementIntent; it does not change Person physical traversal rules.

const RoutePolicyScript = preload("res://scripts/pedestrian_route_policy.gd")
const MovementIntentScript = preload("res://scripts/person_movement_intent.gd")

var route_policy = RoutePolicyScript.new()
var danger_stop_distance_m: float = 3.0

func choose_route(candidates: Array) -> Dictionary:
	return route_policy.choose_route(candidates)

func movement_intent(current_position: Vector3, target_position: Vector3, nearby_vehicle_distance_m: float = INF):
	if nearby_vehicle_distance_m < danger_stop_distance_m:
		return MovementIntentScript.new(Vector2.ZERO, false)
	var delta := target_position - current_position
	var direction := Vector2(delta.x, delta.z)
	return MovementIntentScript.new(direction.normalized() if not direction.is_zero_approx() else Vector2.ZERO, false)
