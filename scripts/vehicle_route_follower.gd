class_name VehicleRouteFollower
extends Node

## Tracks progress on an active GPS polyline and converts AI-driver policy into GPS-owned controls.
##
## Dependencies:
## - Consumes world-space route points, speed limits and explicit upcoming-intersection observations supplied by composition.
## - RouteDrivingPolicy owns speed/curve/intersection policy; the vehicle adapter owns dynamics.
## - Emits reroute_requested on meaningful deviation; it does not calculate routes, traffic, or intersections itself.

signal reroute_requested

const RouteDrivingPolicyScript = preload("res://scripts/route_driving_policy.gd")
const PLAYER_OWNER: int = 0
const GPS_OWNER: int = 1

@export var enabled: bool = false
@export var waypoint_radius_m: float = 5.0
@export var arrival_brake_distance_m: float = 18.0
@export var deviation_distance_m: float = 22.0
@export var lookahead_base_m: float = 8.0
@export var lookahead_speed_seconds: float = 0.8

var vehicle: Node3D = null
var _points: PackedVector3Array = PackedVector3Array()
var _speed_limits_mps: PackedFloat32Array = PackedFloat32Array()
var _target_index: int = 0
var _policy = RouteDrivingPolicyScript.new()
var _deviation_reported: bool = false
var _intersection_index: int = -1
var _intersection_safe_speed_mps: float = 0.0
var _intersection_base_gap_seconds: float = 0.0
var _intersection_observed_gap_seconds: float = INF

func _ready() -> void:
	var parent_node: Node = get_parent()
	if parent_node is Node3D and _is_vehicle_adapter(parent_node):
		vehicle = parent_node as Node3D
	else:
		push_error("VehicleRouteFollower requires a vehicle-compatible Node3D parent")
		set_physics_process(false)
		return
	set_physics_process(true)

func set_route(points: PackedVector3Array, speed_limits_mps: PackedFloat32Array = PackedFloat32Array()) -> void:
	_points = points
	_speed_limits_mps = speed_limits_mps
	_target_index = _forward_target_index()
	clear_upcoming_intersection()

func clear_route() -> void:
	_points = PackedVector3Array()
	_speed_limits_mps = PackedFloat32Array()
	_target_index = 0
	_deviation_reported = false
	clear_upcoming_intersection()
	if vehicle != null and enabled:
		vehicle.call("clear_control_inputs", GPS_OWNER)

func has_route() -> bool:
	return _points.size() >= 2

func set_driving_mode(mode: int) -> bool:
	return _policy.set_mode(mode)

func driving_mode() -> int:
	return _policy.mode()

func set_upcoming_intersection(
	route_point_index: int,
	safe_speed_mps: float,
	base_safe_gap_seconds: float,
	observed_gap_seconds: float
) -> bool:
	if route_point_index < 0 or route_point_index >= _points.size():
		return false
	_intersection_index = route_point_index
	_intersection_safe_speed_mps = maxf(0.0, safe_speed_mps)
	_intersection_base_gap_seconds = maxf(0.1, base_safe_gap_seconds)
	_intersection_observed_gap_seconds = maxf(0.0, observed_gap_seconds)
	return true

func update_intersection_gap(observed_gap_seconds: float) -> void:
	_intersection_observed_gap_seconds = maxf(0.0, observed_gap_seconds)

func clear_upcoming_intersection() -> void:
	_intersection_index = -1
	_intersection_safe_speed_mps = 0.0
	_intersection_base_gap_seconds = 0.0
	_intersection_observed_gap_seconds = INF

func set_follow_enabled(new_enabled: bool) -> bool:
	if new_enabled and not has_route():
		return false
	enabled = new_enabled
	if vehicle == null:
		return false
	vehicle.call("set_control_owner", GPS_OWNER if enabled else PLAYER_OWNER)
	if enabled:
		_target_index = _forward_target_index()
		_deviation_reported = false
	else:
		vehicle.call("clear_control_inputs", PLAYER_OWNER)
	return true

func is_follow_enabled() -> bool:
	return enabled

func _physics_process(_delta: float) -> void:
	if vehicle == null or not has_route():
		return
	_update_progress()
	_monitor_deviation()
	if enabled:
		_drive_route()

func _drive_route() -> void:
	var current := vehicle.global_position
	var speed_mps: float = maxf(float(vehicle.call("speed_mps")), 0.0)
	var target := _lookahead_point(lookahead_base_m + speed_mps * lookahead_speed_seconds)
	var dx := target.x - current.x
	var dz := target.z - current.z
	var desired_heading := atan2(-dx, -dz)
	var heading_error := wrapf(desired_heading - float(vehicle.call("heading_rad")), -PI, PI)
	var max_steer_degrees: float = float(vehicle.get("max_steer_degrees"))
	var steer := clampf(heading_error / deg_to_rad(maxf(max_steer_degrees, 1.0)), -1.0, 1.0)

	var final_point := _target_index >= _points.size() - 1
	if final_point:
		var final_distance := _flat_distance(current, _points[_points.size() - 1])
		if final_distance <= arrival_brake_distance_m:
			var arrival_target := sqrt(maxf(0.0, 2.0 * 3.5 * maxf(final_distance - 1.5, 0.0)))
			var arrival_controls: Vector2 = _policy.controls_for_speed(speed_mps, arrival_target)
			if final_distance <= 2.0:
				arrival_controls = Vector2(0.0, 1.0)
			vehicle.call("set_control_inputs", GPS_OWNER, arrival_controls.x, arrival_controls.y, steer)
			return

	var vehicle_max_speed_mps: float = maxf(float(vehicle.get("max_speed_mps")), 0.0)
	var target_speed: float = _policy.target_speed_mps(_points, _target_index, _speed_limits_mps, speed_mps, vehicle_max_speed_mps)
	if _intersection_index >= _target_index and _intersection_index < _points.size():
		var distance_to_intersection: float = _route_distance_to_index(_intersection_index)
		target_speed = minf(target_speed, _policy.intersection_approach_speed_mps(
			target_speed,
			_intersection_safe_speed_mps,
			distance_to_intersection,
			_intersection_base_gap_seconds,
			_intersection_observed_gap_seconds,
			vehicle_max_speed_mps
		))
	var controls: Vector2 = _policy.controls_for_speed(speed_mps, target_speed)
	if absf(heading_error) > deg_to_rad(70.0):
		controls.x = 0.0
		controls.y = maxf(controls.y, 0.45)
	vehicle.call("set_control_inputs", GPS_OWNER, controls.x, controls.y, steer)

func _update_progress() -> void:
	while _target_index < _points.size() - 1:
		if _flat_distance(vehicle.global_position, _points[_target_index]) <= waypoint_radius_m or _passed_target_plane(_target_index):
			_target_index += 1
			continue
		break
	if _intersection_index >= 0 and _target_index > _intersection_index:
		clear_upcoming_intersection()

func _lookahead_point(distance_m: float) -> Vector3:
	if _points.is_empty():
		return vehicle.global_position if vehicle != null else Vector3.ZERO
	if _points.size() == 1:
		return _points[0]
	var index: int = clampi(_target_index, 1, _points.size() - 1)
	var segment_start: Vector3 = _points[index - 1]
	var segment_end: Vector3 = _points[index]
	var cursor: Vector3 = _closest_point_on_segment(vehicle.global_position, segment_start, segment_end)
	var remaining: float = maxf(distance_m, 0.0)
	while true:
		var segment_remaining: float = _flat_distance(cursor, segment_end)
		if segment_remaining >= remaining and segment_remaining > 0.0001:
			return cursor.lerp(segment_end, remaining / segment_remaining)
		remaining -= segment_remaining
		if index >= _points.size() - 1:
			return _points[_points.size() - 1]
		index += 1
		cursor = segment_end
		segment_end = _points[index]

func _route_distance_to_index(route_point_index: int) -> float:
	if route_point_index < _target_index or route_point_index >= _points.size():
		return 0.0
	var distance: float = _flat_distance(vehicle.global_position, _points[_target_index])
	for index in range(_target_index, route_point_index):
		distance += _flat_distance(_points[index], _points[index + 1])
	return distance

func _forward_target_index() -> int:
	if vehicle == null or _points.is_empty():
		return 0
	var heading: float = float(vehicle.call("heading_rad"))
	var forward := Vector2(-sin(heading), -cos(heading))
	var best_index := 0
	var best_distance_sq := INF
	for index in range(_points.size()):
		var offset := Vector2(_points[index].x - vehicle.global_position.x, _points[index].z - vehicle.global_position.z)
		if offset.length_squared() > 1.0 and offset.normalized().dot(forward) < -0.25:
			continue
		if offset.length_squared() < best_distance_sq:
			best_distance_sq = offset.length_squared()
			best_index = index
	return mini(best_index + 1, _points.size() - 1)

func _monitor_deviation() -> void:
	var distance := _distance_to_upcoming_route()
	if distance > deviation_distance_m and not _deviation_reported:
		_deviation_reported = true
		reroute_requested.emit()
	elif distance < deviation_distance_m * 0.6:
		_deviation_reported = false

func _distance_to_upcoming_route() -> float:
	var best := INF
	var start := maxi(0, _target_index - 1)
	for i in range(start, _points.size() - 1):
		best = minf(best, _distance_to_segment(vehicle.global_position, _points[i], _points[i + 1]))
	return best

func _passed_target_plane(index: int) -> bool:
	if index <= 0 or index >= _points.size():
		return false
	var a := Vector2(_points[index - 1].x, _points[index - 1].z)
	var b := Vector2(_points[index].x, _points[index].z)
	var p := Vector2(vehicle.global_position.x, vehicle.global_position.z)
	var segment := b - a
	if segment.length_squared() < 0.0001:
		return true
	return (p - a).dot(segment) / segment.length_squared() >= 1.0

func _closest_point_on_segment(point: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var p := Vector2(point.x, point.z)
	var av := Vector2(a.x, a.z)
	var bv := Vector2(b.x, b.z)
	var ab := bv - av
	var t := clampf((p - av).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return Vector3(lerpf(a.x, b.x, t), lerpf(a.y, b.y, t), lerpf(a.z, b.z, t))

func _distance_to_segment(point: Vector3, a: Vector3, b: Vector3) -> float:
	var p := Vector2(point.x, point.z)
	var av := Vector2(a.x, a.z)
	var bv := Vector2(b.x, b.z)
	var ab := bv - av
	var t := clampf((p - av).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(av + ab * t)

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()

func _is_vehicle_adapter(node: Node) -> bool:
	return node != null \
		and node.has_method("set_control_owner") \
		and node.has_method("set_control_inputs") \
		and node.has_method("heading_rad") \
		and node.has_method("speed_mps")
