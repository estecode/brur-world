class_name RouteDrivingPolicy
extends RefCounted

## Converts route geometry, speed limits and current speed into forward driving targets.
##
## Dependencies:
## - Uses only meter/m/s route facts, Vector3 geometry, and RouteDrivingProfile data.
## - Does not depend on SceneTree, vehicle nodes, GPS transport or rendering.

const RouteDrivingProfileScript = preload("res://scripts/route_driving_profile.gd")
const DEFAULT_SPEED_MPS: float = 13.9
const MIN_CURVE_SPEED_MPS: float = 4.0

enum Mode {
	NORMAL,
	AGGRESSIVE,
	MANIAC,
}

var _mode: int = Mode.NORMAL
var _profiles: Dictionary = {}

func _init() -> void:
	_profiles = {
		Mode.NORMAL: RouteDrivingProfileScript.new(1.0, 3.2, 3.5, 5.5, 6.0, 0.12, 0.10, 0.55, 0.55),
		Mode.AGGRESSIVE: RouteDrivingProfileScript.new(1.12, 4.4, 5.0, 4.0, 4.5, 0.18, 0.16, 0.80, 0.80),
		Mode.MANIAC: RouteDrivingProfileScript.new(1.35, 6.0, 7.0, 2.5, 3.0, 0.25, 0.22, 1.0, 1.0),
	}

func set_mode(new_mode: int) -> bool:
	if not _profiles.has(new_mode):
		return false
	_mode = new_mode
	return true

func mode() -> int:
	return _mode

func target_speed_mps(
	points: PackedVector3Array,
	target_index: int,
	speed_limits_mps: PackedFloat32Array,
	current_speed_mps: float,
	vehicle_max_speed_mps: float = INF
) -> float:
	if points.size() < 2:
		return 0.0
	var profile = _profile()
	var index := clampi(target_index, 1, points.size() - 1)
	var target: float = _speed_limit_at(index, speed_limits_mps) * float(profile.speed_limit_multiplier)
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
		var curve_speed := maxf(MIN_CURVE_SPEED_MPS, sqrt(float(profile.max_lateral_accel_mps2) * radius_m))
		target = minf(target, _approach_speed(curve_speed, distance_ahead, float(profile.comfort_brake_mps2)))
		var upcoming_limit: float = _speed_limit_at(i + 1, speed_limits_mps) * float(profile.speed_limit_multiplier)
		target = minf(target, _approach_speed(upcoming_limit, distance_ahead, float(profile.comfort_brake_mps2)))
	if is_finite(vehicle_max_speed_mps):
		target = minf(target, maxf(vehicle_max_speed_mps, 0.0))
	return maxf(0.0, target)

func controls_for_speed(current_speed_mps: float, target_speed_mps_value: float) -> Vector2:
	var profile = _profile()
	var error := target_speed_mps_value - maxf(current_speed_mps, 0.0)
	if error > 0.7:
		return Vector2(clampf(error / float(profile.throttle_error_scale_mps), float(profile.minimum_throttle), float(profile.throttle_cap)), 0.0)
	if error < -0.7:
		return Vector2(0.0, clampf(-error / float(profile.brake_error_scale_mps), float(profile.minimum_brake), float(profile.brake_cap)))
	return Vector2(0.0, 0.0)

func _profile():
	return _profiles[_mode]

func _approach_speed(target_mps: float, distance_m: float, braking_mps2: float) -> float:
	return sqrt(maxf(0.0, target_mps * target_mps + 2.0 * braking_mps2 * maxf(distance_m, 0.0)))

func _speed_limit_at(point_index: int, limits: PackedFloat32Array) -> float:
	if limits.is_empty():
		return DEFAULT_SPEED_MPS
	return maxf(1.0, limits[clampi(point_index, 0, limits.size() - 1)])

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()

func _flat_direction(a: Vector3, b: Vector3) -> Vector2:
	return Vector2(b.x - a.x, b.z - a.z).normalized()