extends SceneTree

## Headless integration tests for the production player vehicle, route policy and control ownership boundary.
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

	_assert(bool(player.call("set_control_inputs", PLAYER_OWNER, 1.0, 0.0, 0.0)), "active owner control is accepted")
	_assert(not bool(player.call("set_control_inputs", GPS_OWNER, 1.0, 0.0, 0.0)), "inactive owner control is rejected")
	player.call("_physics_process", 1.0)
	var after_manual = player.call("state_snapshot")
	_assert(after_manual.speed_mps > 0.0, "adapter advances through production dynamics")

	var before_switch = player.call("state_snapshot")
	player.call("set_control_owner", GPS_OWNER)
	var after_switch = player.call("state_snapshot")
	_assert(_same_state(before_switch, after_switch), "switching control owner preserves vehicle state")

	var route := PackedVector3Array([
		player.global_position,
		player.global_position + Vector3(0.0, 0.0, -100.0),
	])
	route_follower.call("set_route", route, PackedFloat32Array([13.9, 13.9]))
	_assert(bool(route_follower.call("set_follow_enabled", true)), "GPS follow can take ownership for an active route")
	_assert(int(player.call("control_owner")) == GPS_OWNER, "GPS owns controls while follow is on")
	route_follower.call("_physics_process", 1.0 / 60.0)
	player.call("_physics_process", 1.0 / 60.0)
	var before_manual_takeover = player.call("state_snapshot")
	_assert(bool(route_follower.call("set_follow_enabled", false)), "follow can be disabled")
	var after_manual_takeover = player.call("state_snapshot")
	_assert(int(player.call("control_owner")) == PLAYER_OWNER, "manual control owns same vehicle after follow off")
	_assert(_same_state(before_manual_takeover, after_manual_takeover), "follow off preserves live vehicle state")
	_assert(bool(route_follower.call("has_route")), "follow off preserves the active route")

	var reroute_count := [0]
	route_follower.connect("reroute_requested", func(): reroute_count[0] += 1)
	player.call("set_world_position", Vector3(180.0, 0.0, 200.0))
	route_follower.call("_physics_process", 1.0 / 60.0)
	_assert(reroute_count[0] == 1, "manual deviation requests a reroute without taking control")
	_assert(int(player.call("control_owner")) == PLAYER_OWNER, "reroute request leaves manual control active")

	var recalculated_route := PackedVector3Array([
		Vector3(100.0, 0.0, 200.0),
		Vector3(100.0, 0.0, 100.0),
		Vector3(100.0, 0.0, 0.0),
	])
	route_follower.call("set_route", recalculated_route, PackedFloat32Array([13.9, 13.9, 13.9]))
	route_follower.call("_physics_process", 1.0 / 60.0)
	_assert(reroute_count[0] == 1, "route replacement does not immediately re-request reroute while still deviated")
	player.call("set_world_position", Vector3(100.0, 0.0, 150.0))
	route_follower.call("_physics_process", 1.0 / 60.0)
	player.call("set_world_position", Vector3(180.0, 0.0, 150.0))
	route_follower.call("_physics_process", 1.0 / 60.0)
	_assert(reroute_count[0] == 2, "returning to the route corridor rearms one later deviation reroute")

	var harness_scene := load("res://harness/driving/driving_harness.tscn") as PackedScene
	_assert(harness_scene != null, "driving harness scene loads")
	var harness: Node = harness_scene.instantiate()
	get_root().add_child(harness)
	await process_frame
	_assert(harness.get_node_or_null("PlayerVehicle") != null, "driving harness instantiates the production player vehicle")
	_assert(harness.get_node_or_null("CameraRig") != null, "driving harness reuses the production camera adapter")
	_assert(harness.get_node_or_null("Roads") != null and harness.get_node("Roads").get_child_count() >= 8, "driving harness provides a connected meter-scale road grid")
	_assert(harness.get_node_or_null("GpsRouteLayer") == null, "driving harness does not require the full world/GPS composition")
	harness.queue_free()

	root.queue_free()
	print("godot vehicle-integration tests: OK")
	quit(0)

func _test_route_policy() -> void:
	var policy = RouteDrivingPolicyScript.new()
	var straight := PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, -40.0), Vector3(0.0, 0.0, -80.0)])
	var curve := PackedVector3Array([Vector3.ZERO, Vector3(0.0, 0.0, -20.0), Vector3(20.0, 0.0, -20.0)])
	var limits := PackedFloat32Array([22.2, 22.2, 22.2])
	var straight_speed: float = policy.target_speed_mps(straight, 1, limits, 15.0)
	var curve_speed: float = policy.target_speed_mps(curve, 1, limits, 15.0)
	_assert(curve_speed < straight_speed, "driver slows before a sharp curve")
	var low_limits := PackedFloat32Array([22.2, 8.3, 8.3])
	_assert(policy.target_speed_mps(straight, 1, low_limits, 15.0) < straight_speed, "driver anticipates a lower upcoming speed limit")
	var braking: Vector2 = policy.controls_for_speed(20.0, 8.0)
	_assert(braking.x == 0.0 and braking.y > 0.0, "driver brakes progressively above target speed")

func _same_state(a, b) -> bool:
	return _approx(a.x_m, b.x_m) and _approx(a.z_m, b.z_m) and _approx(a.heading_rad, b.heading_rad) and _approx(a.speed_mps, b.speed_mps)

func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.00001

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("vehicle-integration test failed: " + message)
	quit(1)
