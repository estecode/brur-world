extends SceneTree

## Deterministic headless coverage for police patrol, observation, speeding and pursuit handoff.

const VehicleScene = preload("res://scenes/vehicle.tscn")
const PoliceObservationStoreScript = preload("res://scripts/police_observation_store.gd")
const PoliceObservationPolicyScript = preload("res://scripts/police_observation_policy.gd")
const PolicePatrolPolicyScript = preload("res://scripts/police_patrol_policy.gd")
const PolicePatrolControllerScript = preload("res://scripts/police_patrol_controller.gd")
const PoliceUnitRuntimeScript = preload("res://scripts/police_unit_runtime.gd")
const PoliceUnitLogicScript = preload("res://scripts/police_unit_logic.gd")
const SpeedingOffenceDetectorScript = preload("res://scripts/speeding_offence_detector.gd")

var failures := 0

class FakeTopology:
	extends RefCounted
	var lengths := {0: 25.0, 1: 25.0, 2: 25.0}
	func has_edge(id: int) -> bool: return lengths.has(id)
	func edge_length_m(id: int) -> float: return float(lengths.get(id, 0.0))
	func edge_speed_mps(_id: int) -> float: return 13.9
	func edge_access_class(id: int) -> int: return 3 if id == 2 else 0
	func outgoing_edge_ids(id: int) -> Array:
		if id == 0: return [2, 1]
		if id == 1: return [0]
		return []
	func edge_world_position(id: int, fraction: float) -> Vector3:
		if id == 0: return Vector3(0,0,-25.0 * fraction)
		if id == 1: return Vector3(25.0 * fraction,0,-25.0)
		return Vector3(-25.0 * fraction,0,-25.0)
	func edge_heading_rad(id: int) -> float: return 0.0 if id == 0 else (PI * 0.5 if id == 1 else -PI * 0.5)
	func edge_progress_from_world(id: int, p: Vector3, fallback: float) -> float:
		if id == 0: return clampf(-p.z, 0.0, 25.0)
		if id == 1: return clampf(p.x, 0.0, 25.0)
		if id == 2: return clampf(-p.x, 0.0, 25.0)
		return fallback

class FakeSpeedQuery:
	extends RefCounted
	var limit := 50.0
	func speed_limit_kmh_at(_position: Vector3) -> Variant: return limit

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	_test_patrol_policy_uses_only_valid_directed_roads()
	_test_police_vehicle_patrols_with_shared_dynamics()
	_test_observation_range_and_visibility_gate_speeding()
	_test_stop_attempt_and_pursuit_handoff()
	_test_detector_is_modular()
	if failures == 0:
		print("police patrol/offence tests: PASS")
		quit(0)
	else:
		push_error("police patrol/offence tests: %d failure(s)" % failures)
		quit(1)

func _test_patrol_policy_uses_only_valid_directed_roads() -> void:
	var policy = PolicePatrolPolicyScript.new(); var topology = FakeTopology.new()
	var chosen := policy.choose_next_edge(topology, 0, 3, 0)
	_assert(chosen == 1, "patrol policy filters forbidden outgoing road and chooses valid directed edge")

func _test_police_vehicle_patrols_with_shared_dynamics() -> void:
	var root := Node.new(); get_root().add_child(root)
	var vehicle := VehicleScene.instantiate() as Node3D; root.add_child(vehicle); vehicle.call("configure", 1)
	var controller := PolicePatrolControllerScript.new(); vehicle.add_child(controller)
	_assert(controller.setup(vehicle, FakeTopology.new(), 0, 4), "police patrol controller accepts valid road edge")
	for i in range(100):
		controller._physics_process(0.1); vehicle._physics_process(0.1)
	_assert(float(vehicle.call("speed_mps")) > 0.5, "police patrol uses shared VehicleDynamics")
	_assert(controller.transition_count >= 1, "police patrol continuously crosses road edges")
	_assert(controller.current_edge_id != 2, "police patrol never enters forbidden edge")
	root.free()

func _test_observation_range_and_visibility_gate_speeding() -> void:
	var root := Node.new(); get_root().add_child(root)
	var police := VehicleScene.instantiate() as Node3D; var player := VehicleScene.instantiate() as Node3D
	root.add_child(police); root.add_child(player)
	police.call("set_world_position", Vector3(0,0,0)); police.call("set_heading_rad", 0.0)
	player.call("set_world_position", Vector3(0,0,-50)); player.call("set_motion_state", 20.0, 0.0)
	var runtime := PoliceUnitRuntimeScript.new(); root.add_child(runtime)
	_assert(runtime.setup("patrol-1", police, player, FakeSpeedQuery.new(), PoliceObservationStoreScript.new()), "police runtime setup succeeds")
	var offence := runtime.sample(10.0, true)
	_assert(offence.get("type", &"") == &"speeding", "near observing police detects clear speeding from actual vehicle speed vs road limit")
	_assert(runtime.logic.state == PoliceUnitLogicScript.State.STOP_ATTEMPT, "speeding transitions police to StopAttempt")

	var far_runtime := PoliceUnitRuntimeScript.new(); root.add_child(far_runtime)
	player.call("set_world_position", Vector3(0,0,-500)); far_runtime.setup("patrol-2", police, player, FakeSpeedQuery.new(), PoliceObservationStoreScript.new())
	_assert(far_runtime.sample(11.0, true).is_empty(), "distant unit does not magically detect speeding")
	player.call("set_world_position", Vector3(0,0,-50))
	var blocked_runtime := PoliceUnitRuntimeScript.new(); root.add_child(blocked_runtime); blocked_runtime.setup("patrol-3", police, player, FakeSpeedQuery.new(), PoliceObservationStoreScript.new())
	_assert(blocked_runtime.sample(12.0, false).is_empty(), "blocked line of sight prevents detection")
	root.free()

func _test_stop_attempt_and_pursuit_handoff() -> void:
	var logic = PoliceUnitLogicScript.new(); logic.add_detector(SpeedingOffenceDetectorScript.new()); logic.pursuit_handoff_after_s = 2.0
	var observation := {"current": true, "speed_mps": 20.0, "source_unit_id": "patrol", "timestamp_s": 1.0}
	_assert(not logic.update_from_observation(observation, 50.0).is_empty(), "observed speeding creates offence")
	logic.step(1.0, false); _assert(logic.state == PoliceUnitLogicScript.State.STOP_ATTEMPT, "StopAttempt persists before timeout")
	logic.step(1.1, false); _assert(logic.state == PoliceUnitLogicScript.State.PURSUIT_HANDOFF, "failed stop attempt reaches pursuit handoff without implementing tactics")
	var handoff := logic.consume_pursuit_handoff(); _assert(not handoff.is_empty() and not (handoff["offence"] as Dictionary).is_empty(), "pursuit handoff carries offence context")

func _test_detector_is_modular() -> void:
	var logic = PoliceUnitLogicScript.new(); var speeding = SpeedingOffenceDetectorScript.new(); logic.add_detector(speeding)
	_assert(logic.detectors.size() == 1 and logic.detectors[0].call("detector_id") == &"speeding", "offence detector is registered as independent policy module")
	var detector = SpeedingOffenceDetectorScript.new()
	_assert(detector.evaluate({"current": true, "speed_mps": 14.3, "source_unit_id": "p", "timestamp_s": 0.0}, 50.0).is_empty(), "small measurement/jitter excess does not trigger clear-speeding simplification")

func _assert(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error(message)
