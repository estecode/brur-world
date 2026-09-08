extends SceneTree

## Headless integration tests for the production player vehicle scene and control ownership boundary.
## Dependencies: scenes/player_vehicle.tscn, Vehicle adapter, player controller, route follower, and driving harness scene.

const PLAYER_OWNER: int = 0
const GPS_OWNER: int = 1

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
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
	route_follower.call("set_route", route)
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

	var harness_scene := load("res://harness/driving/driving_harness.tscn") as PackedScene
	_assert(harness_scene != null, "driving harness scene loads")
	var harness: Node = harness_scene.instantiate()
	_assert(harness.get_node_or_null("GpsRouteLayer") != null, "driving harness reuses production game composition")
	harness.free()

	root.queue_free()
	print("godot vehicle-integration tests: OK")
	quit(0)

func _same_state(a, b) -> bool:
	return _approx(a.x_m, b.x_m) and _approx(a.z_m, b.z_m) and _approx(a.heading_rad, b.heading_rad) and _approx(a.speed_mps, b.speed_mps)

func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.00001

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("vehicle-integration test failed: " + message)
	quit(1)
