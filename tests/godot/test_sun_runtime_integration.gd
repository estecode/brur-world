extends SceneTree

## Verifies that the production game scene uses the astronomical sun while retaining the legacy light as an off-by-default toggle.
## Dependencies: scripts/sun_runtime_controller.gd and scenes/main.tscn; uses an injected time snapshot instead of system time.

const SunRuntimeControllerScript = preload("res://scripts/sun_runtime_controller.gd")

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_main_scene_wiring()
	await _test_runtime_controller()
	call_deferred("_finish")

func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("godot sun runtime integration tests: OK")
	quit(0)

func _test_main_scene_wiring() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_assert(packed != null, "main scene loads")
	if packed == null:
		return
	var scene := packed.instantiate()
	var legacy := scene.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	var astronomical := scene.get_node_or_null("AstronomicalSun") as DirectionalLight3D
	var controller := scene.get_node_or_null("SunRuntimeController")
	var toggle := scene.get_node_or_null("DebugOverlay/LegacyLightToggle") as CheckButton
	_assert(legacy != null, "legacy DirectionalLight3D remains in the game scene")
	_assert(legacy != null and not legacy.visible, "legacy light is off by default")
	_assert(astronomical != null, "astronomical DirectionalLight3D is present in the game scene")
	_assert(controller != null, "game scene contains the astronomical sun runtime controller")
	_assert(toggle != null and not toggle.button_pressed, "legacy light toggle exists and starts off")
	scene.free()

func _test_runtime_controller() -> void:
	var host := Node.new()
	var astronomical := DirectionalLight3D.new()
	astronomical.name = "AstronomicalSun"
	var legacy := DirectionalLight3D.new()
	legacy.name = "DirectionalLight3D"
	legacy.visible = true
	var toggle := CheckButton.new()
	toggle.name = "LegacyLightToggle"
	var controller = SunRuntimeControllerScript.new()
	controller.name = "SunRuntimeController"
	controller.astronomical_light_path = NodePath("../AstronomicalSun")
	controller.legacy_light_path = NodePath("../DirectionalLight3D")
	controller.legacy_toggle_path = NodePath("../LegacyLightToggle")
	controller.set_time_source(func() -> Dictionary:
		return {
			"year": 2026,
			"month": 6,
			"day": 21,
			"hour": 13,
			"minute": 0,
			"second": 0,
			"utc_offset_hours": 2.0,
		}
	)
	host.add_child(astronomical)
	host.add_child(legacy)
	host.add_child(toggle)
	host.add_child(controller)
	root.add_child(host)
	await process_frame
	_assert(astronomical.visible and astronomical.light_energy > 0.0, "astronomical sun actively lights the game during daytime")
	_assert(not legacy.visible, "runtime controller forces legacy light off at startup")
	_assert(not toggle.button_pressed, "legacy toggle starts off")
	toggle.button_pressed = true
	await process_frame
	_assert(legacy.visible, "legacy light can be enabled with the toggle")
	toggle.button_pressed = false
	await process_frame
	_assert(not legacy.visible, "legacy light can be disabled again")
	host.queue_free()
	await process_frame

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("sun runtime integration test failed: " + message)
