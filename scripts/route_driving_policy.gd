class_name RouteDrivingPolicy
extends RefCounted

## Converts route geometry, speed limits and current speed into forward driving targets.
##
## Dependencies:
## - Uses only meter/m/s route facts and Vector3 geometry.
## - Does not depend on SceneTree, vehicle nodes, GPS transport or rendering.

const DEFAULT_SPEED_MPS: float = 13.9
const MIN_CURVE_SPEED_MPS: float = 4.0
const MAX_LATERAL_ACCEL_MPS2: float = 3.2
const COMFORT_BRAKE_MPS2: float = 3.5

func target_speed_mps(points: PackedVector3Array, target_index: int, speed_limits_mps: PackedFloat32Array, current_speed_mps: float) -> float:
	if points.size() < 2:
		return 0.0
	var index := clampi(target_index, 1, points.size() - 1)
	var target := _speed_limit_at(index, speed_limits_mps)
	var distance_ahead := 0.0
	var previous := points[index - 1]
	for i in range(index, mini(points.size() - 1, index + 12)):
		var pivot := points[i]
		distance_ahead += _flat_distance(previous, pivot)
		previous = pivot
		if i + 1 >= points.size():
			break
		var incoming := _flat_direction(points[i - 1], pivot)
		var outgoing := _flat_direction(pivot, points[i + 1])
		if incoming.length_squared() < 0.5 or outgoing.length_squared() < 0.5:
			continue
		var angle := acos(clampf(incoming.dot(outgoing), -1.0, 1.0))
		if angle < deg_to_rad(8.0):
			continue
		var segment_m := maxf(4.0, minf(_flat_distance(points[i - 1], pivot), _flat_distance(pivot, points[i + 1])))
		var radius_m := maxf(3.0, segment_m / maxf(2.0 * sin(angle * 0.5), 0.05))
		var curve_speed := maxf(MIN_CURVE_SPEED_MPS, sqrt(MAX_LATERAL_ACCEL_MPS2 * radius_m))
		target = minf(target, _approach_speed(curve_speed, distance_ahead))
		var upcoming_limit := _speed_limit_at(i + 1, speed_limits_mps)
		target = minf(target, _approach_speed(upcoming_limit, distance_ahead))
	return maxf(0.0, target)

func controls_for_speed(current_speed_mps: float, target_speed_mps_value: float) -> Vector2:
	var error := target_speed_mps_value - maxf(current_speed_mps, 0.0)
	if error > 0.7:
		return Vector2(clampf(error / 4.0, 0.15, 1.0), 0.0)
	if error < -0.7:
		return Vector2(0.0, clampf(-error / 5.0, 0.12, 1.0))
	return Vector2(0.0, 0.0)

func _approach_speed(target_mps: float, distance_m: float) -> float:
	return sqrt(maxf(0.0, target_mps * target_mps + 2.0 * COMFORT_BRAKE_MPS2 * maxf(distance_m, 0.0)))

func _speed_limit_at(point_index: int, limits: PackedFloat32Array) -> float:
	if limits.is_empty():
		return DEFAULT_SPEED_MPS
	return maxf(1.0, limits[clampi(point_index, 0, limits.size() - 1)])

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()

func _flat_direction(a: Vector3, b: Vector3) -> Vector2:
	return Vector2(b.x - a.x, b.z - a.z).normalized()
