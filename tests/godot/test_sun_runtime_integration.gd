extends SceneTree

## Verifies the production astronomical sun, WorldClock wiring, debug time override, and off-by-default legacy light.
## Dependencies: scripts/sun_runtime_controller.gd, scripts/world_clock_runtime.gd, scripts/sun_debug_time_ui.gd, overlay presentation, and scenes/main.tscn.

const SunRuntimeControllerScript = preload("res://scripts/sun_runtime_controller.gd")
const OverlayLayoutScript = preload("res://scripts/overlay_layout.gd")

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
	var world_clock_runtime := scene.get_node_or_null("WorldClockRuntime")
	var controller := scene.get_node_or_null("SunRuntimeController")
	var legacy_toggle := scene.get_node_or_null("DebugOverlay/SunTimeOverride/LegacyLightToggle") as CheckButton
	var time_ui := scene.get_node_or_null("DebugOverlay/SunTimeOverride") as Control
	var time_header := scene.get_node_or_null("DebugOverlay/SunTimeHeader") as Button
	var override_toggle := scene.get_node_or_null("DebugOverlay/SunTimeOverride/OverrideToggle") as CheckButton
	var hour_input := scene.get_node_or_null("DebugOverlay/SunTimeOverride/TimeRow/Hour") as SpinBox
	_assert(legacy != null, "legacy DirectionalLight3D remains in the game scene")
	_assert(legacy != null and not legacy.visible, "legacy light is off by default")
	_assert(astronomical != null, "astronomical DirectionalLight3D is present in the game scene")
	_assert(world_clock_runtime != null, "game scene contains the authoritative WorldClock runtime")
	_assert(controller != null, "game scene contains the astronomical sun runtime controller")
	_assert(controller != null and controller.world_clock_path == NodePath("../WorldClockRuntime"), "sun controller explicitly consumes WorldClockRuntime")
	_assert(controller != null and controller.legacy_toggle_path == NodePath("../DebugOverlay/SunTimeOverride/LegacyLightToggle"), "sun controller explicitly targets the legacy-light control inside the sun/time window")
	_assert(legacy_toggle != null and not legacy_toggle.button_pressed, "legacy light toggle exists inside sun/time and starts off")
	_assert(time_ui != null, "sun time override UI exists")
	_assert(time_header != null, "sun/time has a persistent collapse/restore header")
	_assert(time_header != null and int(time_header.get("slot")) == OverlayLayoutScript.Slot.BOTTOM_LEFT, "overlay presentation owns the sun/time bottom-edge placement")
	_assert(override_toggle != null and not override_toggle.button_pressed, "sun time override starts disabled")
	_assert(hour_input != null and not hour_input.editable, "sun time inputs start locked while WorldClock is authoritative")
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

	var world_clock_basis := astronomical.global_transform.basis
	controller.set_time_override({
		"year": 2026,
		"month": 12,
		"day": 21,
		"hour": 0,
		"minute": 0,
		"second": 0,
		"utc_offset_hours": 0.0,
	})
	_assert(controller.time_override_enabled(), "debug time override can replace WorldClock input")
	_assert(not astronomical.visible and is_zero_approx(astronomical.light_energy), "midnight override immediately changes the astronomical sun")
	controller.set_time_override({
		"year": 2026,
		"month": 6,
		"day": 21,
		"hour": 11,
		"minute": 0,
		"second": 0,
		"utc_offset_hours": 0.0,
	})
	_assert(astronomical.visible and astronomical.light_energy > 0.0, "daytime override immediately restores direct sun")
	_assert(astronomical.global_transform.basis != world_clock_basis, "override changes the sun direction")
	controller.clear_time_override()
	_assert(not controller.time_override_enabled(), "clearing override returns ownership to WorldClock/time source")
	_assert(astronomical.visible and astronomical.light_energy > 0.0, "WorldClock/time source is reapplied after clearing override")

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
