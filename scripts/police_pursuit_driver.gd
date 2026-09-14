class_name PolicePursuitDriver
extends Node

## Drives a police Vehicle along externally calculated pursuit route points.
##
## Dependencies:
## - Vehicle supplies the shared control/dynamics API.
## - Route points/speed limits are supplied by pursuit routing composition.
## - Owns no target prediction, route calculation or tactical action selection.

const POLICE_OWNER := 3

var vehicle: Node3D
var points := PackedVector3Array()
var speed_limits_mps := PackedFloat32Array()
var target_index := 0
var waypoint_radius_m := 4.0

func setup(vehicle_node: Node3D) -> bool:
	vehicle = vehicle_node
	if vehicle == null:
		return false
	vehicle.call("set_control_owner", POLICE_OWNER)
	return true

func set_route(route_points: PackedVector3Array, route_speeds: PackedFloat32Array = PackedFloat32Array()) -> bool:
	if route_points.size() < 2:
		return false
	points = route_points
	speed_limits_mps = route_speeds
	target_index = 1
	return true

func remaining_distance_m() -> float:
	if vehicle == null or points.size() < 2:
		return -1.0
	var distance := vehicle.global_position.distance_to(points[target_index])
	for i in range(target_index, points.size() - 1):
		distance += points[i].distance_to(points[i + 1])
	return distance

func _physics_process(_delta: float) -> void:
	if vehicle == null or points.size() < 2:
		return
	while target_index < points.size() - 1 and vehicle.global_position.distance_to(points[target_index]) <= waypoint_radius_m:
		target_index += 1
	var target := points[target_index]
	var offset := target - vehicle.global_position
	var desired_heading := atan2(offset.x, -offset.z)
	var heading_error := wrapf(desired_heading - float(vehicle.call("heading_rad")), -PI, PI)
	var steer := clampf(heading_error / deg_to_rad(30.0), -1.0, 1.0)
	var target_speed := 18.0
	if target_index < speed_limits_mps.size():
		target_speed = maxf(4.0, float(speed_limits_mps[target_index]) * 1.08)
	var speed := float(vehicle.call("speed_mps"))
	var throttle := 1.0 if speed < target_speed - 0.5 else 0.0
	var brake := 0.35 if speed > target_speed + 1.0 else 0.0
	vehicle.call("set_control_inputs", POLICE_OWNER, throttle, brake, steer)
