extends SceneTree

## Verifies the driving harness compiles and only calls methods exposed by the production CameraRig.
##
## Dependencies:
## - Loads the production-backed driving harness and camera controller scripts.
## - Reads the harness source only to validate its explicit dynamic CameraRig calls; no runtime world data is required.

const HARNESS_SCRIPT_PATH := "res://harness/driving/driving_harness.gd"
const CAMERA_SCRIPT_PATH := "res://scripts/camera_controller.gd"

func _initialize() -> void:
	var harness_script := load(HARNESS_SCRIPT_PATH)
	if harness_script == null:
		_fail("driving harness script failed to load")
		return

	var camera_script := load(CAMERA_SCRIPT_PATH)
	if camera_script == null:
		_fail("camera controller script failed to load")
		return
	var camera_rig := Node3D.new()
	camera_rig.set_script(camera_script)

	var source := FileAccess.get_file_as_string(HARNESS_SCRIPT_PATH)
	if source.is_empty():
		camera_rig.free()
		_fail("driving harness source could not be read")
		return
	var regex := RegEx.new()
	if regex.compile("camera_rig\\.call\\(\\\"([^\\\"]+)\\\"") != OK:
		camera_rig.free()
		_fail("camera call contract regex failed to compile")
		return
	var matches := regex.search_all(source)
	if matches.is_empty():
		camera_rig.free()
		_fail("driving harness exposes no explicit CameraRig calls to validate")
		return
	for match in matches:
		var method_name := StringName(match.get_string(1))
		if not camera_rig.has_method(method_name):
			camera_rig.free()
			_fail("driving harness calls missing CameraRig method: %s" % method_name)
			return

	camera_rig.free()
	print("DRIVING_HARNESS_PARSE=PASS camera_calls=%d" % matches.size())
	quit(0)

func _fail(message: String) -> void:
	push_error("driving harness regression: " + message)
	quit(1)
