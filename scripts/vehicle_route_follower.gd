class_name VehicleRouteFollower
extends Node

## Converts an active GPS route polyline into GPS-owned vehicle control intent.
##
## Dependencies:
## - Consumes world-space route points supplied by GPS composition.
## - Commands the same vehicle adapter used by player input; owns no vehicle dynamics or route calculation.
## - This is a minimal first follower; realistic speed/curve policy remains issue #5.

const PLAYER_OWNER: int = 0
const GPS_OWNER: int = 1

@export var enabled: bool = false
@export var cruise_speed_mps: float = 13.9
@export var waypoint_radius_m: float = 8.0
@export var arrival_brake_distance_m: float = 20.0

var vehicle: Node3D = null
var _points: PackedVector3Array = PackedVector3Array()
var _target_index: int = 0

func _ready() -> void:
	var parent_node: Node = get_parent()
	if parent_node is Node3D and _is_vehicle_adapter(parent_node):
		vehicle = parent_node as Node3D
	else:
		push_error("VehicleRouteFollower requires a vehicle-compatible Node3D parent")
		set_physics_process(false)
		return
	set_physics_process(enabled)

func set_route(points: PackedVector3Array) -> void:
	_points = points
	_target_index = _nearest_target_index()

func clear_route() -> void:
	_points = PackedVector3Array()
	_target_index = 0
	if vehicle != null:
		vehicle.call("clear_control_inputs", GPS_OWNER)

func has_route() -> bool:
	return _points.size() >= 2

func set_follow_enabled(new_enabled: bool) -> bool:
	if new_enabled and not has_route():
		return false
	enabled = new_enabled
	set_physics_process(enabled)
	if vehicle == null:
		return false
	vehicle.call("set_control_owner", GPS_OWNER if enabled else PLAYER_OWNER)
	if enabled:
		_target_index = _nearest_target_index()
	else:
		vehicle.call("clear_control_inputs", PLAYER_OWNER)
	return true

func is_follow_enabled() -> bool:
	return enabled

func _physics_process(_delta: float) -> void:
	if not enabled or vehicle == null:
		return
	if not has_route():
		vehicle.call("set_control_inputs", GPS_OWNER, 0.0, 1.0, 0.0)
		return

	_advance_reached_points()
	var current: Vector3 = vehicle.global_position
	var target: Vector3 = _points[_target_index]
	var dx: float = target.x - current.x
	var dz: float = target.z - current.z
	var distance_m: float = sqrt(dx * dx + dz * dz)
	var desired_heading: float = atan2(-dx, -dz)
	var heading_error: float = wrapf(desired_heading - float(vehicle.call("heading_rad")), -PI, PI)
	var max_steer_degrees: float = float(vehicle.get("max_steer_degrees"))
	var steer: float = clampf(heading_error / deg_to_rad(maxf(max_steer_degrees, 1.0)), -1.0, 1.0)

	var final_point: bool = _target_index >= _points.size() - 1
	if final_point and distance_m <= arrival_brake_distance_m:
		vehicle.call("set_control_inputs", GPS_OWNER, 0.0, 1.0, steer)
		return

	var speed_mps: float = float(vehicle.call("speed_mps"))
	var throttle: float = 1.0 if speed_mps < cruise_speed_mps else 0.0
	var brake: float = 0.0
	if absf(heading_error) > deg_to_rad(55.0) and speed_mps > 6.0:
		brake = 0.5
		throttle = 0.0
	vehicle.call("set_control_inputs", GPS_OWNER, throttle, brake, steer)

func _advance_reached_points() -> void:
	while _target_index < _points.size() - 1:
		var point: Vector3 = _points[_target_index]
		var dx: float = point.x - vehicle.global_position.x
		var dz: float = point.z - vehicle.global_position.z
		if dx * dx + dz * dz > waypoint_radius_m * waypoint_radius_m:
			break
		_target_index += 1

func _nearest_target_index() -> int:
	if vehicle == null or _points.is_empty():
		return 0
	var nearest_index: int = 0
	var nearest_distance_sq: float = INF
	for index in range(_points.size()):
		var point: Vector3 = _points[index]
		var dx: float = point.x - vehicle.global_position.x
		var dz: float = point.z - vehicle.global_position.z
		var distance_sq: float = dx * dx + dz * dz
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest_index = index
	return mini(nearest_index + 1, _points.size() - 1)

func _is_vehicle_adapter(node: Node) -> bool:
	return node != null \
		and node.has_method("set_control_owner") \
		and node.has_method("set_control_inputs") \
		and node.has_method("heading_rad") \
		and node.has_method("speed_mps")
