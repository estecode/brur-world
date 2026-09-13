extends SceneTree

const TrafficSimulationScript = preload("res://scripts/traffic_simulation.gd")
const TrafficTopologyViewScript = preload("res://scripts/traffic_topology_view.gd")
const TrafficRuntimeCompositionScript = preload("res://scripts/traffic_runtime_composition.gd")
const VehicleScene = preload("res://scenes/vehicle.tscn")
const TrafficVehicleControllerScript = preload("res://scripts/traffic_vehicle_controller.gd")

var failures := 0

class FakeTopology:
	extends RefCounted
	var lengths := {0: 100.0, 1: 80.0, 2: 60.0}
	var starts := {0: Vector3(0,0,0), 1: Vector3(0,0,-100), 2: Vector3(80,0,-100)}
	var ends := {0: Vector3(0,0,-100), 1: Vector3(80,0,-100), 2: Vector3(80,0,-160)}
	func has_edge(id: int) -> bool: return lengths.has(id)
	func edge_length_m(id: int) -> float: return float(lengths.get(id, 0.0))
	func edge_speed_mps(_id: int) -> float: return 20.0
	func outgoing_edge_ids(id: int) -> Array:
		if id == 0: return [1]
		if id == 1: return [2]
		return []
	func edge_world_position(id: int, fraction: float) -> Vector3: return starts[id].lerp(ends[id], fraction)
	func edge_heading_rad(id: int) -> float:
		var d: Vector3 = ends[id] - starts[id]
		return atan2(d.x, d.z)
	func edge_progress_from_world(id: int, position: Vector3, fallback: float) -> float:
		if not has_edge(id): return fallback
		var a: Vector3 = starts[id]; var b: Vector3 = ends[id]; var d := Vector2(b.x-a.x, b.z-a.z)
		if d.length_squared() <= 0.001: return fallback
		var t := clampf(Vector2(position.x-a.x, position.z-a.z).dot(d) / d.length_squared(), 0.0, 1.0)
		return t * edge_length_m(id)

func _init() -> void:
	_test_lightweight_progress_and_edge_transition()
	_test_deterministic_choice()
	_test_promotion_hysteresis_and_state_handoff()
	_test_promoted_vehicle_uses_shared_vehicle_dynamics()
	_test_brg1_topology_world_mapping()
	_assert(TrafficRuntimeCompositionScript != null, "traffic runtime composition parses headlessly")
	if failures == 0:
		print("traffic simulation tests: PASS")
		quit(0)
	else:
		push_error("traffic simulation tests: %d failure(s)" % failures)
		quit(1)

func _simulation():
	var sim = TrafficSimulationScript.new(); sim.setup(FakeTopology.new()); return sim

func _test_lightweight_progress_and_edge_transition() -> void:
	var sim = _simulation(); var state = sim.add_agent(1, 0, 90.0, 15.0, 7)
	sim.step(1.0)
	_assert(state.edge_id == 1, "lightweight agent advances onto outgoing edge")
	_assert(absf(state.progress_m - 5.0) < 0.01, "leftover distance is preserved across edge transition")
	_assert(state.next_edge_id == 2, "next directed edge is prepared from shared topology")

func _test_deterministic_choice() -> void:
	var a = _simulation().add_agent(42, 0, 0.0, 10.0, 123)
	var b = _simulation().add_agent(42, 0, 0.0, 10.0, 123)
	_assert(a.next_edge_id == b.next_edge_id, "same seed/state produces deterministic next edge")

func _test_promotion_hysteresis_and_state_handoff() -> void:
	var sim = _simulation(); sim.promotion_radius_m = 20.0; sim.demotion_radius_m = 40.0
	var state = sim.add_agent(2, 0, 10.0, 12.0, 9)
	var req := sim.transition_requests(Vector3(0,0,-10))
	_assert((req["promote"] as Array).has(state), "nearby lightweight agent requests promotion")
	sim.mark_promoted(state)
	var mid := sim.transition_requests(Vector3(0,0,-35))
	_assert(not (mid["demote"] as Array).has(state), "hysteresis prevents immediate demotion")
	var far := sim.transition_requests(Vector3(100,0,100))
	_assert((far["demote"] as Array).has(state), "detailed agent requests demotion outside demotion radius")
	sim.apply_demotion(state, {"position": Vector3(0,0,-25), "speed_mps": 7.5, "next_edge_id": 1, "approach_state": {"signal": "yield"}})
	_assert(not state.detailed and absf(state.progress_m - 25.0) < 0.01, "demotion preserves road-relative position")
	_assert(absf(state.speed_mps - 7.5) < 0.01 and state.next_edge_id == 1, "demotion preserves speed and next edge")
	_assert(state.approach_state.get("signal") == "yield", "demotion preserves approach state")

func _test_promoted_vehicle_uses_shared_vehicle_dynamics() -> void:
	var root := Node.new(); get_root().add_child(root)
	var vehicle := VehicleScene.instantiate() as Node3D; root.add_child(vehicle)
	vehicle.call("set_world_position", Vector3(0,0,-10)); vehicle.call("set_heading_rad", PI); vehicle.call("set_motion_state", 5.0, PI)
	var sim = _simulation(); var state = sim.add_agent(3, 0, 10.0, 12.0, 11); sim.mark_promoted(state)
	var controller := TrafficVehicleControllerScript.new(); vehicle.add_child(controller); controller.setup(vehicle, sim.topology, state)
	_assert(int(vehicle.call("control_owner")) == 2, "promoted traffic owns controls through shared Vehicle API")
	for i in range(8):
		controller._physics_process(0.1); vehicle._physics_process(0.1)
	_assert(float(vehicle.call("speed_mps")) > 5.0, "promoted traffic advances through shared VehicleDynamics")
	root.free()

func _test_brg1_topology_world_mapping() -> void:
	var path := "user://traffic_minimal.brg"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer("BRG1".to_ascii_buffer()); f.store_32(2); f.store_32(1)
	_store_node(f, 1, 1000.0, 2000.0, 0, 1); _store_node(f, 2, 1000.0, 1900.0, 1, 0)
	f.store_64(7); f.store_32(0); f.store_32(0); f.store_32(1); f.store_float(100.0); f.store_float(36.0)
	for value in [0,0,0,0,0,0]: f.store_8(value)
	f.close()
	var topology = TrafficTopologyViewScript.new(); topology.set_world_origin(Vector2(900.0, 2100.0))
	_assert(topology.load_graph(path), "BRG1 traffic topology loads")
	_assert(topology.outgoing_edge_ids(0).is_empty(), "directed topology does not invent outgoing edges")
	var p: Vector3 = topology.edge_world_position(0, 0.5)
	_assert(p.is_equal_approx(Vector3(100.0, 0.0, 150.0)), "BRG1 projected coordinates map through shared world origin convention")
	_assert(absf(topology.edge_speed_mps(0) - 10.0) < 0.001, "BRG1 speed is reused without duplicate traffic policy")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _store_node(f: FileAccess, osm_id: int, x: float, y: float, adjacency_offset: int, adjacency_count: int) -> void:
	f.store_64(osm_id); f.store_double(0.0); f.store_double(0.0); f.store_float(x); f.store_float(y); f.store_32(adjacency_offset); f.store_32(adjacency_count)

func _assert(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error(message)
