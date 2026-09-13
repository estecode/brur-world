extends SceneTree

## Verifies the production Map-to-Manual-Drive camera transition has fixed timing, normalized final leg and safe world clearance.
## Dependencies: scenes/main.tscn production CameraRig and scripts/camera_controller.gd debug snapshot API.

const ALTITUDES := [120.0, 5000.0, 120000.0, 1400000.0]
const STEP_S := 0.01
const TOTAL_S := 1.0
const APPROACH_S := 0.4
const MIN_CLEARANCE_M := 8.0
const TARGET_POSITION := Vector3(240.0, 18.0, -360.0)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var production_scene := load("res://scenes/main.tscn") as PackedScene
	_assert(production_scene != null, "production main scene loads")
	var scene := production_scene.instantiate()
	var production_rig := scene.get_node_or_null("CameraRig") as Node3D
	_assert(production_rig != null, "production main wires CameraRig")
	_assert(is_equal_approx(float(production_rig.get("mode_transition_seconds")), TOTAL_S), "production transition total is 1.0 second")
	_assert(is_equal_approx(float(production_rig.get("drive_transition_approach_fraction")), 0.4), "production approach fraction is 0.4")
	_assert(production_rig.has_method("mode_transition_debug_snapshot"), "production rig exposes transition debug instrumentation")
	scene.free()

	var entry_offsets: Array[Vector3] = []
	var measured_durations: Array[float] = []
	for altitude in ALTITUDES:
		var result := await _run_transition(float(altitude))
		entry_offsets.append(result.entry_offset)
		measured_durations.append(result.duration_s)
		print(
			"CAMERA_TRANSITION_DEBUG altitude_m=%.0f duration_s=%.2f approach_s=%.2f settle_s=%.2f min_clearance_m=%.2f entry_offset=%s final_error_m=%.4f" % [
				float(altitude),
				float(result.duration_s),
				APPROACH_S,
				TOTAL_S - APPROACH_S,
				float(result.min_clearance_m),
				str(result.entry_offset),
				float(result.final_error_m),
			]
		)

	for index in range(1, entry_offsets.size()):
		_assert(entry_offsets[index].distance_to(entry_offsets[0]) < 0.05, "all map altitudes reach the same normalized cinematic entry pose")
	for duration in measured_durations:
		_assert(absf(duration - TOTAL_S) <= STEP_S + 0.001, "transition duration remains fixed at approximately 1.0 second")

	print("godot camera-drive-transition tests: OK")
	quit(0)

func _run_transition(altitude: float) -> Dictionary:
	var production_scene := load("res://scenes/main.tscn") as PackedScene
	var scene := production_scene.instantiate()
	var rig := scene.get_node("CameraRig") as Node3D
	scene.remove_child(rig)
	scene.free()
	root.add_child(rig)
	await process_frame
	rig.set_process(false)

	var target := Node3D.new()
	target.name = "TransitionTarget"
	root.add_child(target)
	target.global_position = TARGET_POSITION
	rig.call("set_follow_target", target)
	rig.call("set_view_altitude", Vector3(-9500.0, 0.0, 7200.0), altitude)
	rig.call("set_drive_mode", true)

	var camera := rig.get_node("Camera3D") as Camera3D
	var elapsed := 0.0
	var min_clearance := INF
	var entry_offset := Vector3(INF, INF, INF)
	var before_boundary := Vector3.ZERO
	var after_boundary := Vector3.ZERO
	var sampled_before := false
	var sampled_entry := false
	var sampled_after := false
	while bool(rig.call("is_mode_transition_active")) and elapsed < 1.2:
		rig.call("_process", STEP_S)
		elapsed += STEP_S
		var snapshot: Dictionary = rig.call("mode_transition_debug_snapshot")
		var clearance := float(snapshot.get("clearance_m", -INF))
		min_clearance = minf(min_clearance, clearance)
		_assert(clearance + 0.001 >= MIN_CLEARANCE_M, "camera never enters the blue/below-world clearance zone at altitude %.0f" % altitude)
		_assert(camera.global_position.y + 0.001 >= TARGET_POSITION.y + MIN_CLEARANCE_M, "camera stays above target/world surface at every transition sample")
		if not sampled_before and elapsed >= APPROACH_S - STEP_S:
			before_boundary = camera.global_position
			sampled_before = true
		if not sampled_entry and elapsed >= APPROACH_S:
			entry_offset = camera.global_position - target.global_position
			_assert(str(snapshot.get("phase", "")) in ["approach", "settle"], "phase boundary is instrumented")
			sampled_entry = true
		if not sampled_after and elapsed >= APPROACH_S + STEP_S:
			after_boundary = camera.global_position
			sampled_after = true

	_assert(sampled_entry and sampled_after, "transition samples the normalized entry and settle phase")
	_assert(before_boundary.distance_to(after_boundary) < 20.0, "phase boundary has no discontinuous camera teleport")
	_assert(not bool(rig.call("is_mode_transition_active")), "transition completes")
	_assert(absf(elapsed - TOTAL_S) <= STEP_S + 0.001, "total transition time is independent of map altitude")
	var expected_final := TARGET_POSITION + Vector3(0.0, float(rig.get("drive_height_m")), float(rig.get("drive_distance_m")))
	var final_error := camera.global_position.distance_to(expected_final)
	_assert(final_error < 0.05, "final camera pose matches normal Manual Drive pose")
	var debug: Dictionary = rig.call("mode_transition_debug_snapshot")
	_assert(absf(float(debug.get("approach_s", -1.0)) - APPROACH_S) < 0.001, "approach phase is exactly 0.4 seconds")
	_assert(absf(float(debug.get("settle_s", -1.0)) - 0.6) < 0.001, "settle phase is exactly 0.6 seconds")

	target.queue_free()
	rig.queue_free()
	await process_frame
	return {
		"entry_offset": entry_offset,
		"duration_s": elapsed,
		"min_clearance_m": min_clearance,
		"final_error_m": final_error,
	}

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("camera-drive-transition test failed: " + message)
	quit(1)
