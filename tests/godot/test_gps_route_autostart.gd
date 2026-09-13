extends SceneTree

## Verifies that installing any valid GPS route immediately gives the route follower GPS control.
## Dependencies: production player_vehicle.tscn and VehicleRouteFollower public APIs only.

const PLAYER_OWNER: int = 0
const GPS_OWNER: int = 1

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var player_scene := load("res://scenes/player_vehicle.tscn") as PackedScene
	_assert(player_scene != null, "player vehicle scene loads")
	var player: Node3D = player_scene.instantiate() as Node3D
	root.add_child(player)
	await process_frame

	var follower: Node = player.get_node_or_null("VehicleRouteFollower")
	_assert(follower != null, "production player exposes route follower")
	_assert(int(player.call("control_owner")) == PLAYER_OWNER, "vehicle starts in manual ownership before a route exists")

	var first_route := PackedVector3Array([
		Vector3.ZERO,
		Vector3(0.0, 0.0, -50.0),
		Vector3(0.0, 0.0, -100.0),
	])
	follower.call("set_route", first_route, PackedFloat32Array([13.9, 13.9, 13.9]))
	_assert(bool(follower.call("is_follow_enabled")), "setting a valid route enables GPS follow automatically")
	_assert(int(player.call("control_owner")) == GPS_OWNER, "setting a valid route gives GPS control ownership")

	_assert(bool(follower.call("set_follow_enabled", false)), "manual takeover remains available")
	_assert(int(player.call("control_owner")) == PLAYER_OWNER, "manual takeover releases GPS ownership")

	var replacement_route := PackedVector3Array([
		Vector3.ZERO,
		Vector3(50.0, 0.0, -50.0),
		Vector3(100.0, 0.0, -100.0),
	])
	follower.call("set_route", replacement_route, PackedFloat32Array([11.1, 11.1, 11.1]))
	_assert(bool(follower.call("is_follow_enabled")), "setting a replacement route re-enters GPS follow after manual takeover")
	_assert(int(player.call("control_owner")) == GPS_OWNER, "replacement route always restores GPS ownership")

	player.queue_free()
	print("godot GPS route-autostart tests: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("GPS route-autostart test failed: " + message)
	quit(1)
