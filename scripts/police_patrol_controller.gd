class_name PolicePatrolController
extends Node

## Drives one police Vehicle continuously along valid shared road topology.
##
## Dependencies:
## - Vehicle provides the shared control/dynamics API.
## - PolicePatrolPolicy chooses outgoing roads; topology is injected read-only.
## - No observation, offence or pursuit-tactics dependency.

const PolicePatrolPolicyScript = preload("res://scripts/police_patrol_policy.gd")
const POLICE_OWNER := 3

var vehicle: Node3D
var topology
var policy = PolicePatrolPolicyScript.new()
var current_edge_id := -1
var next_edge_id := -1
var transition_count := 0
var unit_seed := 1
var cruise_fraction := 0.82

func setup(vehicle_node: Node3D, topology_view, start_edge_id: int, seed: int = 1) -> bool:
	vehicle = vehicle_node; topology = topology_view; current_edge_id = start_edge_id; unit_seed = maxi(seed, 1)
	if vehicle == null or topology == null or not bool(topology.call("has_edge", current_edge_id)): return false
	if topology.has_method("edge_access_class") and int(topology.call("edge_access_class", current_edge_id)) > 1: return false
	next_edge_id = policy.choose_next_edge(topology, current_edge_id, unit_seed, transition_count)
	vehicle.call("set_control_owner", POLICE_OWNER)
	var start: Vector3 = topology.call("edge_world_position", current_edge_id, 0.0)
	var heading := float(topology.call("edge_heading_rad", current_edge_id))
	vehicle.call("set_world_position", start)
	vehicle.call("set_heading_rad", heading)
	return true

func _physics_process(_delta: float) -> void:
	if vehicle == null or topology == null or current_edge_id < 0: return
	var progress := float(topology.call("edge_progress_from_world", current_edge_id, vehicle.global_position, 0.0))
	var edge_len := float(topology.call("edge_length_m", current_edge_id))
	if edge_len - progress <= 2.0:
		if next_edge_id < 0:
			vehicle.call("set_control_inputs", POLICE_OWNER, 0.0, 1.0, 0.0); return
		current_edge_id = next_edge_id; transition_count += 1
		next_edge_id = policy.choose_next_edge(topology, current_edge_id, unit_seed, transition_count)
	var target_heading := float(topology.call("edge_heading_rad", current_edge_id))
	var error := wrapf(target_heading - float(vehicle.call("heading_rad")), -PI, PI)
	var steer := clampf(error / deg_to_rad(30.0), -1.0, 1.0)
	var limit := float(topology.call("edge_speed_mps", current_edge_id))
	var target_speed := maxf(2.0, limit * cruise_fraction)
	var speed := float(vehicle.call("speed_mps"))
	var throttle := 1.0 if speed < target_speed - 0.5 else 0.0
	var brake := 0.5 if speed > target_speed + 0.8 else 0.0
	vehicle.call("set_control_inputs", POLICE_OWNER, throttle, brake, steer)
