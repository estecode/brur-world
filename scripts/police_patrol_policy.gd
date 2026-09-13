class_name PolicePatrolPolicy
extends RefCounted

## Chooses the next patrol edge from an injected read-only road-topology API.
##
## Dependencies:
## - No Vehicle, SceneTree, observation, offence or pursuit dependency.
## - The topology owner remains authoritative for legal directed outgoing edges.

func choose_next_edge(topology, current_edge_id: int, unit_seed: int, transition_count: int) -> int:
	if topology == null or not bool(topology.call("has_edge", current_edge_id)):
		return -1
	var outgoing_value: Variant = topology.call("outgoing_edge_ids", current_edge_id)
	if typeof(outgoing_value) != TYPE_ARRAY:
		return -1
	var candidates: Array = []
	for edge_value in outgoing_value:
		var edge_id := int(edge_value)
		if not bool(topology.call("has_edge", edge_id)):
			continue
		if topology.has_method("edge_access_class") and int(topology.call("edge_access_class", edge_id)) > 1:
			continue
		candidates.append(edge_id)
	if candidates.is_empty():
		return -1
	var mixed := int((maxi(1, unit_seed) * 1103515245 + transition_count * 2654435761) & 0x7fffffff)
	return int(candidates[mixed % candidates.size()])
