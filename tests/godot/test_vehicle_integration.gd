extends SceneTree

## Headless integration tests for production vehicle, AI driving policy and control ownership.
## Dependencies: player vehicle scene, RouteDrivingPolicy, route follower, and driving harness scene.

const RouteDrivingPolicyScript = preload("res://scripts/route_driving_policy.gd")
const PLAYER_OWNER: int = 0
const GPS_OWNER: int = 1

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_route_policy()
	var player_scene := load("res://scenes/player_vehicle.tscn") as PackedScene
	_assert(player_scene != null, "player vehicle scene loads")
	var player: Node3D = player_scene.instantiate() as Node3D
	_assert(player != null, "player vehicle scene instantiates the production vehicle adapter")

	var root := Node.new()
	get_root().add_child(root)
	root.add_child(player)
	player.call("set_world_position", Vector3(100.0, 0.0, 200.0))

	var player_controller: Node = player.get_node_or_null("PlayerVehicleController")
	var route_follower: Node = player.get_node_or_null("VehicleRouteFollower")
	_assert(player_controller != null, "player scene wires production player controller")
	_assert(route_follower != null, "player scene wires production route follower")
	_assert(int(player.call("control_owner")) == PLAYER_OWNER, "player owns controls initially")

	_assert(bool(player.call("set_control_inputs", PLAYER_OWNER, 1.0, 0.0, 0.0)), "active manual owner control is accepted")
	_assert(not bool(player.call("set_control_inputs", GPS_OWNER, 1.0, 0.0, 0.0)), "inactive GPS owner control is rejected")
	player.call("_physics_process", 1.0)
	var after_manual = player.call("state_snapshot")
	_assert(after_manual.speed_mps > 0.0, "manual input advances through production dynamics")

	var route := PackedVector3Array([
		player.global_position,
		player.global_position + Vector3(0.0, 0.0, -100.0),
		player.global_position + Vector3(100.0, 0.0, -100.0),
	])
	route_follower.call("set_route", route, PackedFloat32Array([13.9, 13.9, 13.9]))
	var before_mode_switch = player.call("state_snapshot")
	_assert(int(route_follower.call("driving_mode")) == RouteDrivingPolicyScript.Mode.NORMAL, "route follower defaults to Normal AI policy")
	_assert(bool(route_follower.call("set_driving_mode", RouteDrivingPolicyScript.Mode.AGGRESSIVE)), "AI driving mode changes at runtime")
	_assert(bool(route_follower.call("has_route")), "changing AI mode preserves active route")
	_assert(_same_state(before_mode_switch, player.call("state_snapshot")), "changing AI mode preserves vehicle state")
	_assert(not bool(route_follower.call("set_driving_mode", 999)), "invalid AI driving modes fail closed")

	_assert(bool(route_follower.call("set_follow_enabled", true)), "GPS drive can take ownership for an active route")
	_assert(int(player.call("control_owner")) == GPS_OWNER, "GPS owns controls while AI drive is enabled")
	var before_manual_takeover = player.call("state_snapshot")
	_assert(bool(route_follower.call("set_follow_enabled", false)), "AI drive can release ownership")
	_assert(int(player.call("control_owner")) == PLAYER_OWNER, "manual control owns same vehicle after AI drive off")
	_assert(_same_state(before_manual_takeover, player.call("state_snapshot")), "ownership switch preserves live vehicle state")
	_assert(bool(route_follower.call("has_route")), "manual takeover preserves active GPS route")

	var harness_scene := load("res://harness/driving/driving_harness.tscn") as PackedScene
	_assert(harness_scene != null, "driving harness scene loads")
	var harness: Node = harness_scene.instantiate()
	get_root().add_child(harness)
	await process_frame
	_assert(harness.get_node_or_null("PlayerVehicle") != null, "driving harness instantiates production player vehicle")
	_assert(harness.get_node_or_null("CameraRig") != null, "driving harness reuses production camera adapter")
	_assert(harness.get_node_or_null("Roads") != null and harness.get_node("Roads").get_child_count() >= 8, "driving harness provides connected road grid")
	harness.queue_free()

	root.queue_free()
	print("godot vehicle-integration tests: OK")
	quit(0)

func _test_route_policy() -> void:
	var policy = RouteDrivingPolicyScript.new()
	var straight := PackedVector3Array([
		Vector3.ZERO,
		Vector3(0.0, 0.0, -50.0),
		Vector3(0.0, 0.0, -100.0),
		Vector3(0.0, 0.0, -150.0),
	])
	var gentle_curve := PackedVector3Array([
		Vector3.ZERO,
		Vector3(0.0, 0.0, -40.0),
		Vector3(20.0, 0.0, -75.0),
		Vector3(55.0, 0.0, -95.0),
	])
	var sharp_curve := PackedVector3Array([
		Vector3.ZERO,
		Vector3(0.0, 0.0, -20.0),
		Vector3(20.0, 0.0, -20.0),
		Vector3(40.0, 0.0, -20.0),
	])
	var limits := PackedFloat32Array([13.9, 13.9, 13.9, 13.9])
	var vehicle_max := 50.0

	_assert(policy.set_mode(RouteDrivingPolicyScript.Mode.NORMAL), "Normal policy selected")
	var normal_straight: float = policy.target_speed_mps(straight, 1, limits, 5.0, vehicle_max)
	var normal_gentle: float = policy.target_speed_mps(gentle_curve, 1, limits, 5.0, vehicle_max)
	var normal_sharp: float = policy.target_speed_mps(sharp_curve, 1, limits, 5.0, vehicle_max)
	_assert(_approx_tolerance(normal_straight, 13.9, 0.05), "Normal targets approximately the road speed limit on a straight")
	_assert(normal_sharp < normal_gentle and normal_gentle <= normal_straight, "sharper route geometry produces a lower Normal curve target")

	_assert(policy.set_mode(RouteDrivingPolicyScript.Mode.AGGRESSIVE), "Aggressive policy selected")
	var aggressive_straight: float = policy.target_speed_mps(straight, 1, limits, 5.0, vehicle_max)
	var aggressive_sharp: float = policy.target_speed_mps(sharp_curve, 1, limits, 5.0, vehicle_max)
	_assert(_approx_tolerance(aggressive_straight, 13.9 * 1.3, 0.08), "Aggressive targets about 1.3x the road speed limit on a straight")
	_assert(aggressive_sharp > normal_sharp, "Aggressive carries more speed through the same sharp curve")

	_assert(policy.set_mode(RouteDrivingPolicyScript.Mode.MANIAC), "Maniac policy selected")
	var maniac_straight: float = policy.target_speed_mps(straight, 1, limits, 5.0, vehicle_max)
	var maniac_sharp: float = policy.target_speed_mps(sharp_curve, 1, limits, 5.0, vehicle_max)
	_assert(_approx_tolerance(maniac_straight, vehicle_max, 0.05), "Maniac targets vehicle maximum speed instead of a speed-limit multiplier on a straight")
	_assert(maniac_sharp > aggressive_sharp, "Maniac carries the most speed through the same sharp curve")
	_assert(maniac_sharp <= vehicle_max + 0.001, "curve policy never exceeds vehicle max speed")

	var throttles: Array[float] = []
	var brakes: Array[float] = []
	var gaps: Array[float] = []
	var intersection_speeds: Array[float] = []
	for mode in [RouteDrivingPolicyScript.Mode.NORMAL, RouteDrivingPolicyScript.Mode.AGGRESSIVE, RouteDrivingPolicyScript.Mode.MANIAC]:
		_assert(policy.set_mode(mode), "known driving policy mode is accepted")
		var first_curve_speed: float = policy.target_speed_mps(sharp_curve, 1, limits, 15.0, vehicle_max)
		var second_curve_speed: float = policy.target_speed_mps(sharp_curve, 1, limits, 15.0, vehicle_max)
		_assert(_approx(first_curve_speed, second_curve_speed), "curve output is deterministic in every mode")
		throttles.append(policy.controls_for_speed(5.0, 25.0).x)
		brakes.append(policy.controls_for_speed(25.0, 5.0).y)
		gaps.append(policy.accepted_gap_seconds(4.0))
		intersection_speeds.append(policy.intersection_approach_speed_mps(30.0, 8.0, 12.0, 4.0, 8.0, vehicle_max))
		_assert(policy.target_speed_mps(straight, 1, PackedFloat32Array([50.0, 50.0, 50.0, 50.0]), 20.0, 24.0) <= 24.0 + 0.001, "vehicle max speed hard-caps every AI mode")
		var bounded_controls: Vector2 = policy.controls_for_speed(0.0, 100.0)
		_assert(bounded_controls.x <= 1.0 and bounded_controls.y <= 1.0, "AI controls never exceed dynamics input limits")

	_assert(throttles[0] < throttles[1] and throttles[1] <= throttles[2], "Normal Aggressive Maniac use increasingly assertive acceleration")
	_assert(brakes[0] < brakes[1] and brakes[1] <= brakes[2], "Normal Aggressive Maniac use increasingly hard braking")
	_assert(gaps[0] > gaps[1] and gaps[1] > gaps[2], "intersection accepted safety gap shrinks Normal to Aggressive to Maniac")
	_assert(intersection_speeds[0] < intersection_speeds[1] and intersection_speeds[1] < intersection_speeds[2], "intersection approach speed increases Normal to Aggressive to Maniac")

	_assert(policy.set_mode(RouteDrivingPolicyScript.Mode.NORMAL), "Normal policy restored")
	var normal_blocked: float = policy.intersection_approach_speed_mps(25.0, 8.0, 8.0, 4.0, 3.0, vehicle_max)
	_assert(policy.set_mode(RouteDrivingPolicyScript.Mode.AGGRESSIVE), "Aggressive policy restored")
	var aggressive_gap: float = policy.intersection_approach_speed_mps(25.0, 8.0, 8.0, 4.0, 3.0, vehicle_max)
	_assert(normal_blocked < aggressive_gap, "a 3-second gap makes Normal more cautious than Aggressive")
	_assert(policy.set_mode(RouteDrivingPolicyScript.Mode.MANIAC), "Maniac policy restored")
	var maniac_gap: float = policy.intersection_approach_speed_mps(25.0, 8.0, 8.0, 4.0, 2.0, vehicle_max)
	_assert(maniac_gap > 0.0, "Maniac accepts a deterministic risky 2-second intersection gap")

func _same_state(a, b) -> bool:
	return _approx(a.x_m, b.x_m) and _approx(a.z_m, b.z_m) and _approx(a.heading_rad, b.heading_rad) and _approx(a.speed_mps, b.speed_mps)

func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.00001

func _approx_tolerance(a: float, b: float, tolerance: float) -> bool:
	return absf(a - b) <= tolerance

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("vehicle-integration test failed: " + message)
	quit(1)
