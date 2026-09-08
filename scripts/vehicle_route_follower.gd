class_name VehicleRouteFollower
extends Node

## Converts an active GPS route polyline into GPS-owned Vehicle control intent.
##
## Dependencies:
## - Consumes world-space route points supplied by GPS composition.
## - Commands the same Vehicle adapter used by player input; owns no vehicle dynamics or route calculation.
## - This is a minimal first follower; realistic speed/curve policy remains issue #5.

@export var enabled: bool = false
@export var cruise_speed_mps: float = 13.9
@export var waypoint_radius_m: float = 8.0
@export var arrival_brake_distance_m: float = 20.0

var vehicle: Vehicle = null
var _points: PackedVector3Array = PackedVector3Array()
var _target_index: int = 0

func _ready() -> void:
	var parent_node := get_parent()
	if parent_node is Vehicle:
		vehicle = parent_node as Vehicle
	else:
		push_error("VehicleRouteFollower requires a Vehicle parent")
		set_physics_process(false)
	set_physics_process(enabled)

func set_route(points: PackedVector3Array) -> void:
	_points = points
	_target_index = _nearest_target_index()

func clear_route() -> void:
	_points = PackedVector3Array()
	_target_index = 0
	if vehicle != null:
		vehicle.clear_control_inputs(Vehicle.ControlOwner.GPS)

func has_route() -> bool:
	return _points.size() >= 2

func set_follow_enabled(new_enabled: bool) -> bool:
	if new_enabled and not has_route():
		return false
	enabled = new_enabled
	set_physics_process(enabled)
	if vehicle == null:
		return false
	vehicle.set_control_owner(Vehicle.ControlOwner.GPS if enabled else Vehicle.ControlOwner.PLAYER)
	if enabled:
		_target_index = _nearest_target_index()
	else:
		vehicle.clear_control_inputs(Vehicle.ControlOwner.PLAYER)
	return true

func is_follow_enabled() -> bool:
	return enabled

func _physics_process(_delta: float) -> void:
	if not enabled or vehicle == null:
		return
	if not has_route():
		vehicle.set_control_inputs(Vehicle.ControlOwner.GPS, 0.0, 1.0, 0.0)
		return

	_advance_reached_points()
	var current := vehicle.global_position
	var target := _points[_target_index]
	var dx: float = target.x - current.x
	var dz: float = target.z - current.z
	var distance_m: float = sqrt(dx * dx + dz * dz)
	var desired_heading: float = atan2(-dx, -dz)
	var heading_error: float = wrapf(desired_heading - vehicle.heading_rad(), -PI, PI)
	var steer: float = clampf(heading_error / deg_to_rad(maxf(vehicle.max_steer_degrees, 1.0)), -1.0, 1.0)

	var final_point: bool = _target_index >= _points.size() - 1
	if final_point and distance_m <= arrival_brake_distance_m:
		vehicle.set_control_inputs(Vehicle.ControlOwner.GPS, 0.0, 1.0, steer)
		return

	var throttle: float = 1.0 if vehicle.speed_mps() < cruise_speed_mps else 0.0
	var brake: float = 0.0
	if absf(heading_error) > deg_to_rad(55.0) and vehicle.speed_mps() > 6.0:
		brake = 0.5
		throttle = 0.0
	vehicle.set_control_inputs(Vehicle.ControlOwner.GPS, throttle, brake, steer)

func _advance_reached_points() -> void:
	while _target_index < _points.size() - 1:
		var point := _points[_target_index]
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
		var point := _points[index]
		var dx: float = point.x - vehicle.global_position.x
		var dz: float = point.z - vehicle.global_position.z
		var distance_sq: float = dx * dx + dz * dz
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest_index = index
	return mini(nearest_index + 1, _points.size() - 1)
