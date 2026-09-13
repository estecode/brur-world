extends SceneTree

## Verifies that every AI driving style uses the real post-slip vehicle state to recover toward the route.
## Dependencies: production player vehicle scene, VehicleRouteFollower, RouteDrivingPolicy and shared VehicleDynamics.

const RouteDrivingPolicyScript = preload("res://scripts/route_driving_policy.gd")
const PLAYER_OWNER: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var player_scene := load("res://scenes/player_vehicle.tscn") as PackedScene
	_assert(player_scene != null, "player vehicle scene loads")
	var root := Node.new()
	get_root().add_child(root)

	for mode in [RouteDrivingPolicyScript.Mode.NORMAL, RouteDrivingPolicyScript.Mode.AGGRESSIVE, RouteDrivingPolicyScript.Mode.MANIAC]:
		_test_mode_recovers_after_physical_slip(player_scene, root, mode)

	root.queue_free()
	print("godot vehicle-route-recovery tests: OK")
	quit(0)

func _test_mode_recovers_after_physical_slip(player_scene: PackedScene, root: Node, mode: int) -> void:
	var car: Node3D = player_scene.instantiate() as Node3D
	root.add_child(car)
	var follower: Node = car.get_node("VehicleRouteFollower")
	car.call("set_world_position", Vector3(12.0, 0.0, 0.0))
	car.call("set_motion_state", 25.0, 0.0)

	# Create a real shared-physics loss-of-line state before handing control to GPS.
	_assert(bool(car.call("set_control_inputs", PLAYER_OWNER, 0.7, 0.35, -1.0)), "manual owner can request saturated precondition controls")
	for _index in range(60):
		car.call("_physics_process", 1.0 / 60.0)
	var slipped_state = car.call("state_snapshot")
	_assert(absf(slipped_state.last_slip_angle_rad) > 0.10, "recovery precondition contains physical body/trajectory slip")

	var route_z: float = car.global_position.z
	var route := PackedVector3Array([
		Vector3(0.0, 0.0, route_z + 20.0),
		Vector3(0.0, 0.0, route_z - 100.0),
		Vector3(0.0, 0.0, route_z - 220.0),
		Vector3(0.0, 0.0, route_z - 340.0),
	])
	follower.call("set_route", route, PackedFloat32Array([13.9, 13.9, 13.9, 13.9]))
	_assert(bool(follower.call("set_driving_mode", mode)), "AI mode is accepted for recovery regression")
	_assert(bool(follower.call("set_follow_enabled", true)), "GPS takes control of the slipped vehicle without reset")

	var initial_cross_track: float = absf(car.global_position.x)
	var best_cross_track: float = initial_cross_track
	for _index in range(240):
		follower.call("_physics_process", 1.0 / 60.0)
		car.call("_physics_process", 1.0 / 60.0)
		best_cross_track = minf(best_cross_track, absf(car.global_position.x))

	_assert(best_cross_track < initial_cross_track * 0.75, "every AI style materially reduces route error after real physical slip")
	car.queue_free()

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("vehicle-route-recovery test failed: " + message)
	quit(1)
