extends SceneTree

## Headless deterministic tests for real-world camera altitude and its Godot adapter.
##
## Dependencies:
## - scripts/camera_altitude_model.gd for portable altitude behavior.
## - scripts/camera_controller.gd for thin Camera3D integration.
## - scenes/main.tscn for structural altitude-readout placement.

const CameraAltitudeModelScript = preload("res://scripts/camera_altitude_model.gd")
const CameraControllerScript = preload("res://scripts/camera_controller.gd")
const NORMAL_CLOUD_TOP_M: float = 12000.0

func _init() -> void:
	_test_altitude_model()
	_test_altitude_ui_structure()
	call_deferred("_test_camera_adapter")

func _test_altitude_model() -> void:
	var model = CameraAltitudeModelScript.new(50.0, 1400000.0, 10000.0)
	_assert(is_equal_approx(model.get_altitude(), 10000.0), "initial altitude is deterministic")
	model.zoom_by(2.0)
	_assert(is_equal_approx(model.get_altitude(), 20000.0), "zoom out increases altitude monotonically")
	model.zoom_by(0.5)
	_assert(is_equal_approx(model.get_altitude(), 10000.0), "inverse zoom returns to the same altitude")
	model.set_altitude(-1.0)
	_assert(is_equal_approx(model.get_altitude(), 50.0), "50 metre minimum altitude is enforced")
	model.set_altitude(2000000.0)
	_assert(is_equal_approx(model.get_altitude(), 1400000.0), "maximum altitude is enforced")
	_assert(model.get_altitude() > NORMAL_CLOUD_TOP_M, "maximum altitude is above the configured normal cloud range")
	_assert(CameraAltitudeModelScript.format_altitude(50.0) == "Camera: 50 m", "50 metre readout remains in metres")
	_assert(CameraAltitudeModelScript.format_altitude(999.4) == "Camera: 999 m", "metres are used below one kilometre")
	_assert(CameraAltitudeModelScript.format_altitude(1000.0) == "Camera: 1.0 km", "readout switches to kilometres at one kilometre")

func _test_altitude_ui_structure() -> void:
	var packed_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	_assert(packed_scene != null, "main scene loads for altitude UI validation")
	var scene: Node = packed_scene.instantiate()
	var rig: Node = scene.get_node("CameraRig")
	var altitude_ui: CanvasLayer = scene.get_node("CameraAltitudeUi") as CanvasLayer
	var panel: Control = scene.get_node("CameraAltitudeUi/Panel") as Control
	var label: Label = scene.get_node("CameraAltitudeUi/Panel/Label") as Label
	_assert(is_equal_approx(float(rig.get("min_altitude_m")), 50.0), "production map camera exposes the 50 metre minimum")
	_assert(altitude_ui != null, "altitude UI exists in the production scene")
	_assert(altitude_ui.layer >= 20, "altitude readout renders above the normal HUD")
	_assert(panel != null and is_equal_approx(panel.anchor_left, 0.5) and is_equal_approx(panel.anchor_right, 0.5), "altitude readout is anchored at top centre, away from left debug overlay")
	_assert(panel.offset_top >= 0.0 and panel.offset_bottom > panel.offset_top, "altitude readout has a visible vertical extent")
	_assert(label != null and label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "altitude text is centred in its compact panel")
	scene.free()

func _test_camera_adapter() -> void:
	var rig: Node3D = Node3D.new()
	rig.name = "CameraRig"
	rig.set_script(CameraControllerScript)
	rig.set("min_altitude_m", 50.0)
	rig.set("max_altitude_m", 1400000.0)
	rig.set("start_altitude_m", 10000.0)
	var camera: Camera3D = Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	root.add_child(rig)
	await process_frame

	_assert(is_equal_approx(float(rig.call("get_altitude")), 10000.0), "adapter exposes authoritative altitude")
	_assert(is_equal_approx(camera.position.y, 10000.0), "Camera3D physical height equals authoritative altitude")
	var normal_pitch_deg := rad_to_deg(float(rig.call("_pitch_radians")))
	rig.call("set_altitude", 50.0)
	var low_pitch_deg := rad_to_deg(float(rig.call("_pitch_radians")))
	_assert(is_equal_approx(float(rig.call("get_altitude")), 50.0), "adapter reaches exactly 50 metres")
	_assert(is_equal_approx(camera.position.y, 50.0), "Camera3D physical height reaches exactly 50 metres")
	_assert(low_pitch_deg > normal_pitch_deg, "low-altitude map tilt becomes steeper for usable close framing")
	_assert(low_pitch_deg > 57.0 and low_pitch_deg < 59.0, "50 metre tilt reaches the defined low-altitude pose")
	_assert(camera.near <= 1.0, "near plane adapts for close map viewing")
	var distance_50m: float = float(rig.call("get_distance"))
	_assert(distance_50m >= 50.0 and distance_50m < 80.0, "50 metre derived camera distance stays compact and finite")
	rig.call("set_altitude", 749.0)
	var pitch_before_transition := rad_to_deg(float(rig.call("_pitch_radians")))
	rig.call("set_altitude", 751.0)
	var pitch_after_transition := rad_to_deg(float(rig.call("_pitch_radians")))
	_assert(absf(pitch_before_transition - pitch_after_transition) < 0.25, "low-altitude tilt blends continuously into normal map tilt")
	rig.call("set_altitude", -100.0)
	_assert(is_equal_approx(float(rig.call("get_altitude")), 50.0), "adapter clamps below 50 metres")
	rig.call("set_altitude", 20000.0)
	var far_distance: float = float(rig.call("get_distance"))
	_assert(far_distance > distance_50m, "derived view distance increases when altitude increases")
	rig.call("set_altitude", 2000000.0)
	_assert(is_equal_approx(float(rig.call("get_altitude")), 1400000.0), "adapter applies model maximum")
	_assert(camera.position.y > NORMAL_CLOUD_TOP_M, "full zoom-out camera can be above ordinary cloud layers")

	rig.queue_free()
	print("godot camera-altitude tests: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("camera-altitude test failed: " + message)
	quit(1)
