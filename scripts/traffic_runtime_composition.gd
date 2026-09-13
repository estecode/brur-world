class_name TrafficRuntimeComposition
extends Node3D

## Composes the traffic domain into production runtime.
## BRG1 stays authoritative for road topology; TrafficSimulation owns only per-agent road-relative state.

const TrafficTopologyViewScript = preload("res://scripts/traffic_topology_view.gd")
const TrafficSimulationScript = preload("res://scripts/traffic_simulation.gd")
const TrafficVehicleControllerScript = preload("res://scripts/traffic_vehicle_controller.gd")
const VehicleScene = preload("res://scenes/vehicle.tscn")
const GRAPH_PATH := "res://world_data/routing.brg"

@export var main_path: NodePath
@export var route_layer_path: NodePath
@export var camera_rig_path: NodePath
@export var ambient_agent_count := 512
@export var simulation_hz := 10.0

var topology = TrafficTopologyViewScript.new()
var simulation = TrafficSimulationScript.new()
var detailed_by_id: Dictionary = {}
var marker_multimesh: MultiMesh
var marker_instance: MultiMeshInstance3D
var _accum := 0.0

func _ready() -> void:
	var main := get_node_or_null(main_path)
	if main == null or not main.has_method("get_world_coordinates"): return
	var coords = main.call("get_world_coordinates")
	topology.set_world_origin(coords.origin)
	if not topology.load_graph(GRAPH_PATH): return
	simulation.setup(topology)
	_seed_agents()
	_setup_markers()

func _process(delta: float) -> void:
	if simulation.agents.is_empty(): return
	_accum += delta
	var interval := 1.0 / maxf(1.0, simulation_hz)
	if _accum < interval: return
	var step_delta := _accum; _accum = 0.0
	simulation.step(step_delta)
	_apply_transitions()
	_update_lightweight_markers()

func _seed_agents() -> void:
	var usable: Array[int] = []
	for edge_id in range(topology.edges.size()):
		var edge: Dictionary = topology.edges[edge_id]
		if int(edge["access_class"]) <= 1 and float(edge["speed_kmh"]) > 0.0:
			usable.append(edge_id)
	if usable.is_empty(): return
	var count := mini(ambient_agent_count, usable.size())
	var stride := maxi(1, usable.size() / count)
	for i in range(count):
		var edge_id := usable[(i * stride) % usable.size()]
		var len := topology.edge_length_m(edge_id)
		var speed := minf(topology.edge_speed_mps(edge_id), 13.9 + float(i % 5))
		simulation.add_agent(i + 1, edge_id, fmod(float(i * 37), maxf(1.0, len)), speed, i + 17)

func _setup_markers() -> void:
	marker_multimesh = MultiMesh.new()
	marker_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	marker_multimesh.instance_count = simulation.agents.size()
	var box := BoxMesh.new(); box.size = Vector3(1.8, 1.0, 4.2)
	marker_multimesh.mesh = box
	marker_instance = MultiMeshInstance3D.new(); marker_instance.name = "LightweightTraffic"; marker_instance.multimesh = marker_multimesh
	add_child(marker_instance)
	_update_lightweight_markers()

func _relevance_position() -> Vector3:
	var route_layer := get_node_or_null(route_layer_path)
	if route_layer != null and route_layer.has_method("get_player_vehicle"):
		var player := route_layer.call("get_player_vehicle") as Node3D
		if player != null: return player.global_position
	var camera_rig := get_node_or_null(camera_rig_path) as Node3D
	return camera_rig.global_position if camera_rig != null else Vector3.ZERO

func _apply_transitions() -> void:
	var requests := simulation.transition_requests(_relevance_position())
	for state in requests["promote"]: _promote(state)
	for state in requests["demote"]: _demote(state)

func _promote(state) -> void:
	if detailed_by_id.has(state.agent_id): return
	var snapshot := simulation.world_snapshot(state)
	if snapshot.is_empty(): return
	var vehicle := VehicleScene.instantiate() as Node3D
	vehicle.name = "TrafficVehicle%d" % state.agent_id
	vehicle.call("set_world_position", snapshot["position"])
	vehicle.call("set_heading_rad", snapshot["heading_rad"])
	vehicle.call("set_motion_state", snapshot["speed_mps"], snapshot["heading_rad"])
	add_child(vehicle)
	var controller := TrafficVehicleControllerScript.new()
	controller.name = "TrafficVehicleController"
	vehicle.add_child(controller)
	controller.setup(vehicle, topology, state)
	detailed_by_id[state.agent_id] = {"vehicle": vehicle, "controller": controller}
	simulation.mark_promoted(state)

func _demote(state) -> void:
	if not detailed_by_id.has(state.agent_id): return
	var entry: Dictionary = detailed_by_id[state.agent_id]
	var controller: Node = entry["controller"]
	var vehicle: Node3D = entry["vehicle"]
	simulation.apply_demotion(state, controller.call("snapshot_for_demotion"))
	detailed_by_id.erase(state.agent_id)
	vehicle.queue_free()

func _update_lightweight_markers() -> void:
	if marker_multimesh == null: return
	for i in range(simulation.agents.size()):
		var state = simulation.agents[i]
		if state.detailed:
			marker_multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0.0, -1000000.0, 0.0)))
			continue
		var snapshot := simulation.world_snapshot(state)
		if snapshot.is_empty(): continue
		var basis := Basis(Vector3.UP, float(snapshot["heading_rad"]))
		marker_multimesh.set_instance_transform(i, Transform3D(basis, snapshot["position"] + Vector3(0.0, 0.5, 0.0)))
