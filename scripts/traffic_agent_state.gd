class_name TrafficAgentState
extends RefCounted

## Stores the cheap road-relative state for one ambient traffic unit.
##
## Dependencies:
## - Contains only traffic-domain state and no SceneTree, rendering, GPS, police or routing implementation dependency.
## - TrafficSimulation advances this state using an injected read-only road-topology API.

var agent_id: int = 0
var edge_id: int = -1
var progress_m: float = 0.0
var speed_mps: float = 0.0
var next_edge_id: int = -1
var transition_count: int = 0
var random_seed: int = 1
var detailed: bool = false
var approach_state: Dictionary = {}

func duplicate_state():
	var copy := TrafficAgentState.new()
	copy.agent_id = agent_id
	copy.edge_id = edge_id
	copy.progress_m = progress_m
	copy.speed_mps = speed_mps
	copy.next_edge_id = next_edge_id
	copy.transition_count = transition_count
	copy.random_seed = random_seed
	copy.detailed = detailed
	copy.approach_state = approach_state.duplicate(true)
	return copy
