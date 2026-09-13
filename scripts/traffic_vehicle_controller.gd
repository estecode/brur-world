class_name TrafficVehicleController
extends Node

## Drives a promoted ambient traffic Vehicle through the shared VehicleDynamics control API.
## Lightweight TrafficAgentState remains the handoff truth for road edge/progress/next-edge state.

const TRAFFIC_OWNER := 2
var vehicle: Node3D
var topology
var agent_state

func setup(vehicle_node: Node3D, topology_view, state) -> void:
	vehicle = vehicle_node; topology = topology_view; agent_state = state
	vehicle.call("set_control_owner", TRAFFIC_OWNER)

func _physics_process(_delta: float) -> void:
	if vehicle == null or topology == null or agent_state == null: return
	var edge_id := int(agent_state.edge_id)
	if not bool(topology.call("has_edge", edge_id)): return
	agent_state.progress_m = float(topology.call("edge_progress_from_world", edge_id, vehicle.global_position, agent_state.progress_m))
	var edge_len := float(topology.call("edge_length_m", edge_id))
	if edge_len - agent_state.progress_m <= 2.0 and agent_state.next_edge_id >= 0 and bool(topology.call("has_edge", agent_state.next_edge_id)):
		agent_state.edge_id = agent_state.next_edge_id
		agent_state.progress_m = 0.0
		agent_state.transition_count += 1
		var outgoing: Array = topology.call("outgoing_edge_ids", agent_state.edge_id)
		agent_state.next_edge_id = int(outgoing[agent_state.transition_count % outgoing.size()]) if not outgoing.is_empty() else -1
		edge_id = agent_state.edge_id
	var target_heading := float(topology.call("edge_heading_rad", edge_id))
	var heading_error := wrapf(target_heading - float(vehicle.call("heading_rad")), -PI, PI)
	var steer := clampf(heading_error / deg_to_rad(28.0), -1.0, 1.0)
	var target_speed := minf(float(agent_state.speed_mps), float(topology.call("edge_speed_mps", edge_id)))
	var current_speed := float(vehicle.call("speed_mps"))
	var throttle := 1.0 if current_speed < target_speed - 0.4 else 0.0
	var brake := 0.6 if current_speed > target_speed + 0.8 else 0.0
	vehicle.call("set_control_inputs", TRAFFIC_OWNER, throttle, brake, steer)

func snapshot_for_demotion() -> Dictionary:
	if vehicle == null: return {}
	return {"position": vehicle.global_position, "speed_mps": float(vehicle.call("speed_mps")), "next_edge_id": int(agent_state.next_edge_id), "approach_state": agent_state.approach_state.duplicate(true)}
