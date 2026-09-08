extends SceneTree

## Headless deterministic tests for real-world camera altitude and its Godot adapter.
##
## Dependencies:
## - scripts/camera_altitude_model.gd for portable altitude behavior.
## - scripts/camera_controller.gd for thin Camera3D integration.

const CameraAltitudeModelScript = preload("res://scripts/camera_altitude_model.gd")
const CameraControllerScript = preload("res://scripts/camera_controller.gd")
const NORMAL_CLOUD_TOP_M: float = 12000.0

func _init() -> void:
	_test_altitude_model()
	call_deferred("_test_camera_adapter")

func _test_altitude_model() -> void:
	var model = CameraAltitudeModelScript.new(1000.0, 1400000.0, 10000.0)
	_assert(is_equal_approx(model.get_altitude(), 10000.0), "initial altitude is deterministic")
	model.zoom_by(2.0)
	_assert(is_equal_approx(model.get_altitude(), 20000.0), "zoom out increases altitude monotonically")
	model.zoom_by(0.5)
	_assert(is_equal_approx(model.get_altitude(), 10000.0), "inverse zoom returns to the same altitude")
	model.set_altitude(-1.0)
	_assert(is_equal_approx(model.get_altitude(), 1000.0), "minimum altitude is enforced")
	model.set_altitude(2000000.0)
	_assert(is_equal_approx(model.get_altitude(), 1400000.0), "maximum altitude is enforced")
	_assert(model.get_altitude() > NORMAL_CLOUD_TOP_M, "maximum altitude is above the configured normal cloud range")
	_assert(CameraAltitudeModelScript.format_altitude(999.4) == "Camera: 999 m", "metres are used below one kilometre")
	_assert(CameraAltitudeModelScript.format_altitude(1000.0) == "Camera: 1.0 km", "readout switches to kilometres at one kilometre")
	_assert(CameraAltitudeModelScript.format_altitude(8400.0) == "Camera: 8.4 km", "kilometre formatting is stable")

func _test_camera_adapter() -> void:
	var rig: Node3D = Node3D.new()
	rig.name = "CameraRig"
	rig.set_script(CameraControllerScript)
	rig.set("min_altitude_m", 1000.0)
	rig.set("max_altitude_m", 1400000.0)
	rig.set("start_altitude_m", 10000.0)
	var camera: Camera3D = Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	root.add_child(rig)
	await process_frame

	_assert(is_equal_approx(float(rig.call("get_altitude")), 10000.0), "adapter exposes authoritative altitude")
	_assert(is_equal_approx(camera.position.y, 10000.0), "Camera3D physical height equals authoritative altitude")
	var near_distance: float = float(rig.call("get_distance"))
	rig.call("set_altitude", 20000.0)
	var far_distance: float = float(rig.call("get_distance"))
	_assert(is_equal_approx(camera.position.y, 20000.0), "setting altitude updates Camera3D height")
	_assert(far_distance > near_distance, "derived view distance increases when altitude increases")
	rig.call("set_altitude", -100.0)
	_assert(is_equal_approx(float(rig.call("get_altitude")), 1000.0), "adapter applies model minimum")
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
