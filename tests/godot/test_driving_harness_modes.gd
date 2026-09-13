extends SceneTree

## Verifies the driving harness exposes exclusive Manual/GPS ownership and AI policy controls.
## Dependencies: production-backed driving harness scene, CameraRig and VehicleRouteFollower public APIs.

const PLAYER_OWNER: int = 0
const GPS_OWNER: int = 1

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://harness/driving/driving_harness.tscn") as PackedScene
	_assert(scene != null, "driving harness scene loads")
	var harness := scene.instantiate()
	get_root().add_child(harness)
	await process_frame

	var control := harness.get_node_or_null("Ui/Panel/Margin/VBox/ControlMode") as OptionButton
	var selector := harness.get_node_or_null("Ui/Panel/Margin/VBox/DrivingMode") as OptionButton
	var intersection := harness.get_node_or_null("Ui/Panel/Margin/VBox/IntersectionGap") as OptionButton
	var camera := harness.get_node_or_null("CameraRig")
	var player := harness.get_node_or_null("PlayerVehicle")
	_assert(control != null and control.item_count == 2, "harness exposes Manual Drive and GPS Drive")
	_assert(control.get_item_text(0) == "Manual Drive", "first control mode is Manual Drive")
	_assert(control.get_item_text(1) == "GPS Drive", "second control mode is GPS Drive")
	_assert(selector != null and selector.item_count == 3, "harness exposes exactly three AI policy modes")
	_assert(intersection != null and intersection.item_count == 3, "harness exposes deterministic intersection-gap scenarios")
	_assert(player != null, "driving harness uses production player vehicle")
	_assert(camera != null, "driving harness uses production camera")

	var follower := player.get_node_or_null("VehicleRouteFollower")
	var player_controller := player.get_node_or_null("PlayerVehicleController")
	_assert(follower != null, "driving harness uses production route follower")
	_assert(player_controller != null, "driving harness uses production player controller")

	_assert(int(player.call("control_owner")) == PLAYER_OWNER, "Manual Drive owns the vehicle initially")
	_assert(bool(player_controller.get("enabled")), "player controller is enabled in Manual Drive")
	_assert(not bool(follower.call("is_follow_enabled")), "GPS follower is disabled in Manual Drive")
	_assert(bool(camera.call("is_driving_view")), "Manual Drive reserves camera drive mode so WASD cannot pan the map")
	_assert(selector.disabled, "AI style selector is disabled in Manual Drive")

	control.select(1)
	control.item_selected.emit(1)
	await process_frame
	_assert(int(player.call("control_owner")) == GPS_OWNER, "GPS Drive owns the same vehicle")
	_assert(not bool(player_controller.get("enabled")), "player controller is disabled in GPS Drive")
	_assert(bool(follower.call("is_follow_enabled")), "route follower is enabled in GPS Drive")
	_assert(not bool(camera.call("is_driving_view")), "GPS Drive releases WASD for map pan")
	_assert(not selector.disabled, "AI style selector is enabled only in GPS Drive")

	var player_instance := player
	for index in range(3):
		selector.select(index)
		selector.item_selected.emit(index)
		await process_frame
		_assert(int(follower.call("driving_mode")) == selector.get_item_id(index), "selector updates production AI policy mode")
		_assert(harness.get_node_or_null("PlayerVehicle") == player_instance, "AI mode switching keeps the same production vehicle instance")
		_assert(int(player.call("control_owner")) == GPS_OWNER, "AI mode switching does not change control ownership")

	control.select(0)
	control.item_selected.emit(0)
	await process_frame
	_assert(int(player.call("control_owner")) == PLAYER_OWNER, "switching back restores manual owner")
	_assert(bool(player_controller.get("enabled")), "player controller returns without respawning the car")
	_assert(not bool(follower.call("is_follow_enabled")), "GPS follower releases the vehicle on manual takeover")
	_assert(bool(camera.call("is_driving_view")), "manual takeover again suppresses map WASD")
	_assert(harness.get_node_or_null("PlayerVehicle") == player_instance, "manual/GPS ownership switching preserves vehicle instance")

	harness.queue_free()
	print("DRIVING_HARNESS_MODES=PASS")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("driving-harness mode test failed: " + message)
	quit(1)
