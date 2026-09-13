class_name TrafficSimulation
extends RefCounted

## Advances ambient traffic cheaply in road-relative state.
##
## Dependencies:
## - Consumes an injected read-only topology API; never owns or rebuilds roads.
## - TrafficAgentState owns per-agent state.
## - No SceneTree, rendering, GPS, police or Vehicle dependency.

const TrafficAgentStateScript = preload("res://scripts/traffic_agent_state.gd")

var topology = null
var agents: Array = []
var promotion_radius_m: float = 180.0
var demotion_radius_m: float = 240.0
var max_promotions_per_tick: int = 8
var max_demotions_per_tick: int = 8

func setup(read_only_topology) -> void:
	topology = read_only_topology

func add_agent(agent_id: int, edge_id: int, progress_m: float, speed_mps: float, random_seed: int = 1):
	if topology == null or not bool(topology.call("has_edge", edge_id)):
		return null
	var state := TrafficAgentStateScript.new()
	state.agent_id = agent_id
	state.edge_id = edge_id
	state.progress_m = clampf(progress_m, 0.0, float(topology.call("edge_length_m", edge_id)))
	state.speed_mps = maxf(0.0, speed_mps)
	state.random_seed = max(1, random_seed)
	state.next_edge_id = _choose_next_edge(state)
	agents.append(state)
	return state

func step(delta: float) -> void:
	if topology == null or delta <= 0.0:
		return
	for state in agents:
		if not state.detailed:
			_advance_lightweight(state, delta)

func world_snapshot(state) -> Dictionary:
	if topology == null or state == null or not bool(topology.call("has_edge", state.edge_id)):
		return {}
	var edge_length := maxf(0.001, float(topology.call("edge_length_m", state.edge_id)))
	var fraction := clampf(state.progress_m / edge_length, 0.0, 1.0)
	return {
		"position": topology.call("edge_world_position", state.edge_id, fraction),
		"heading_rad": float(topology.call("edge_heading_rad", state.edge_id)),
		"speed_mps": state.speed_mps,
		"edge_id": state.edge_id,
		"progress_m": state.progress_m,
		"next_edge_id": state.next_edge_id,
		"approach_state": state.approach_state.duplicate(true),
	}

func transition_requests(relevance_position: Vector3) -> Dictionary:
	var promote: Array = []
	var demote: Array = []
	var promotion_radius_sq := promotion_radius_m * promotion_radius_m
	var demotion_radius_sq := demotion_radius_m * demotion_radius_m
	for state in agents:
		var snapshot := world_snapshot(state)
		if snapshot.is_empty():
			continue
		var position: Vector3 = snapshot["position"]
		var dx := position.x - relevance_position.x
		var dz := position.z - relevance_position.z
		var distance_sq := dx * dx + dz * dz
		if not state.detailed and distance_sq <= promotion_radius_sq and promote.size() < max_promotions_per_tick:
			promote.append(state)
		elif state.detailed and distance_sq >= demotion_radius_sq and demote.size() < max_demotions_per_tick:
			demote.append(state)
	return {"promote": promote, "demote": demote}

func mark_promoted(state) -> void:
	if state != null:
		state.detailed = true

func apply_demotion(state, detailed_snapshot: Dictionary) -> void:
	if state == null or topology == null:
		return
	var position_value: Variant = detailed_snapshot.get("position", Vector3.INF)
	if position_value is Vector3 and (position_value as Vector3).is_finite():
		state.progress_m = clampf(float(topology.call("edge_progress_from_world", state.edge_id, position_value, state.progress_m)), 0.0, float(topology.call("edge_length_m", state.edge_id)))
	state.speed_mps = maxf(0.0, float(detailed_snapshot.get("speed_mps", state.speed_mps)))
	if detailed_snapshot.has("approach_state") and typeof(detailed_snapshot["approach_state"]) == TYPE_DICTIONARY:
		state.approach_state = (detailed_snapshot["approach_state"] as Dictionary).duplicate(true)
	state.next_edge_id = int(detailed_snapshot.get("next_edge_id", state.next_edge_id))
	state.detailed = false

func _advance_lightweight(state, delta: float) -> void:
	if not bool(topology.call("has_edge", state.edge_id)):
		return
	var allowed_speed := maxf(0.0, float(topology.call("edge_speed_mps", state.edge_id)))
	var travel_speed := minf(state.speed_mps, allowed_speed) if allowed_speed > 0.0 else state.speed_mps
	var remaining := maxf(0.0, travel_speed * delta)
	var safety_guard := 0
	while remaining > 0.0 and safety_guard < 64:
		safety_guard += 1
		var edge_length := maxf(0.001, float(topology.call("edge_length_m", state.edge_id)))
		var available := maxf(0.0, edge_length - state.progress_m)
		if remaining < available:
			state.progress_m += remaining
			break
		remaining -= available
		state.progress_m = edge_length
		if state.next_edge_id < 0 or not bool(topology.call("has_edge", state.next_edge_id)):
			state.next_edge_id = _choose_next_edge(state)
		if state.next_edge_id < 0:
			state.speed_mps = 0.0
			break
		state.edge_id = state.next_edge_id
		state.progress_m = 0.0
		state.transition_count += 1
		state.next_edge_id = _choose_next_edge(state)
		var new_limit := maxf(0.0, float(topology.call("edge_speed_mps", state.edge_id)))
		if new_limit > 0.0:
			state.speed_mps = minf(state.speed_mps, new_limit)

func _choose_next_edge(state) -> int:
	if topology == null or state == null:
		return -1
	var outgoing_value: Variant = topology.call("outgoing_edge_ids", state.edge_id)
	if typeof(outgoing_value) != TYPE_ARRAY:
		return -1
	var outgoing: Array = outgoing_value
	if outgoing.is_empty():
		return -1
	var mixed := int((state.random_seed * 1103515245 + state.agent_id * 12345 + state.transition_count * 2654435761) & 0x7fffffff)
	return int(outgoing[mixed % outgoing.size()])
