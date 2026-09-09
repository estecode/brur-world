class_name VehicleRouteFollower
extends Node

## Tracks progress on an active GPS polyline and converts route policy into GPS-owned controls.
##
## Dependencies:
## - Consumes world-space route points and optional per-point speed limits supplied by GPS composition.
## - RouteDrivingPolicy owns speed/curve policy; the vehicle adapter owns dynamics.
## - Emits reroute_requested on meaningful deviation; it does not calculate routes itself.

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
	_deviation_reported = false

func clear_route() -> void:
	_points = PackedVector3Array()
	_speed_limits_mps = PackedFloat32Array()
	_target_index = 0
	_deviation_reported = false
	if vehicle != null and enabled:
		vehicle.call("clear_control_inputs", GPS_OWNER)

func has_route() -> bool:
	return _points.size() >= 2

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
	var target_index := _lookahead_index(lookahead_base_m + speed_mps * lookahead_speed_seconds)
	var target := _points[target_index]
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

	var target_speed: float = _policy.target_speed_mps(_points, _target_index, _speed_limits_mps, speed_mps)
	var controls: Vector2 = _policy.controls_for_speed(speed_mps, target_speed)
	if absf(heading_error) > deg_to_rad(70.0):
		controls.x = 0.0
		controls.y = maxf(controls.y, 0.45)
	vehicle.call("set_control_inputs", GPS_OWNER, controls.x, controls.y, steer)

func _update_progress() -> void:
	while _target_index < _points.size() - 1:
		if _flat_distance(vehicle.global_position, _points[_target_index]) > waypoint_radius_m:
			break
		_target_index += 1

func _lookahead_index(distance_m: float) -> int:
	var index := _target_index
	var remaining := maxf(distance_m, 0.0)
	var cursor := vehicle.global_position
	while index < _points.size() - 1:
		var segment := _flat_distance(cursor, _points[index])
		if segment >= remaining:
			break
		remaining -= segment
		cursor = _points[index]
		index += 1
	return index

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
