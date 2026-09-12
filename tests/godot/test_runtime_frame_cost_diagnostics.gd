extends SceneTree

## Measures production per-frame script paths in isolation to separate CPU work from renderer cost.
##
## Dependencies:
## - Exercises the real production scripts with minimal explicit scene fixtures.
## - Uses Godot's headless dummy renderer, so results measure script/CPU work rather than GPU cost.

const MainScript = preload("res://scripts/main.gd")
const CameraScript = preload("res://scripts/camera_controller.gd")
const CloudScript = preload("res://scripts/cloud_field_renderer.gd")
const PoiScript = preload("res://scripts/poi_layer.gd")
const CityLightsScript = preload("res://scripts/city_light_renderer.gd")
const DebugOverlayScript = preload("res://scripts/debug_overlay.gd")

var _failed := false

class DummyCameraRig:
	extends Node3D
	var distance_m := 760000.0
	var focus := Vector3.ZERO
	func get_distance() -> float:
		return distance_m
	func get_altitude() -> float:
		return distance_m
	func get_focus_world() -> Vector3:
		return focus
	func get_ground_view_corners() -> PackedVector3Array:
		return PackedVector3Array([
			Vector3(-700000.0, 0.0, -360000.0),
			Vector3(700000.0, 0.0, -360000.0),
			Vector3(700000.0, 0.0, 360000.0),
			Vector3(-700000.0, 0.0, 360000.0),
		])

class DummyMain:
	extends Node3D
	var current_lod := 0
	var loaded := {}
	var mesh_cache := {}
	var last_min_tile := Vector2i(38, 273)
	var last_max_tile := Vector2i(83, 296)
	var current_layer_spacing := 133.2
	func consume_perf_metrics() -> Dictionary:
		return {
			"road_build_ms": 0.0,
			"road_build_max_ms": 0.0,
			"road_tiles_built": 0,
			"road_pending": 0,
			"road_refresh_ms": 0.0,
			"road_cache_hits": 0,
			"road_cache_misses": 0,
		}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var results := {}
	results["camera_idle"] = await _bench_camera()
	results["main_idle"] = await _bench_main()
	results["poi_far_idle"] = await _bench_poi_far()
	results["city_lights_visibility"] = await _bench_city_lights()
	results["debug_overlay"] = await _bench_debug_overlay()
	results["cloud_update"] = await _bench_clouds()

	var total_non_cloud := 0.0
	for name in ["camera_idle", "main_idle", "poi_far_idle", "city_lights_visibility", "debug_overlay"]:
		total_non_cloud += float(results[name])
	print("FRAME_DIAG total_non_cloud_avg_ms=%.4f cloud_avg_ms=%.4f" % [total_non_cloud, float(results["cloud_update"])])
	print("FRAME_DIAG interpretation=headless script costs are CPU-side only; persistent ~132 ms on Mac requires renderer/platform investigation if these remain small")

	if _failed:
		quit(1)
		return
	print("runtime frame-cost diagnostics: OK")
	quit(0)

func _bench_camera() -> float:
	var rig = CameraScript.new()
	rig.name = "CameraRig"
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	get_root().add_child(rig)
	await process_frame
	var avg := _measure("camera_idle", Callable(rig, "_process").bind(0.0), 2000)
	rig.queue_free()
	await process_frame
	return avg

func _bench_main() -> float:
	var main = MainScript.new()
	main.name = "MainFixture"
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var world := Node3D.new()
	world.name = "World"
	main.add_child(world)
	var rig := DummyCameraRig.new()
	rig.name = "CameraRig"
	main.add_child(rig)
	var light := DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	main.add_child(light)
	var environment := WorldEnvironment.new()
	environment.name = "WorldEnvironment"
	main.add_child(environment)
	get_root().add_child(main)
	await process_frame
	# _ready exits because CI has no world_data; set the minimal state needed to
	# execute the steady-state production _process path without refreshing files.
	main.manifest = {"format": "BRT1"}
	main.current_layer_spacing = main._layer_spacing()
	var avg := _measure("main_idle", Callable(main, "_process").bind(0.0), 2000)
	main.queue_free()
	await process_frame
	return avg

func _bench_poi_far() -> float:
	var parent := Node3D.new()
	parent.name = "PoiFixture"
	parent.process_mode = Node.PROCESS_MODE_DISABLED
	var rig := DummyCameraRig.new()
	rig.name = "CameraRig"
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	parent.add_child(rig)
	var poi = PoiScript.new()
	poi.name = "PoiLayer"
	parent.add_child(poi)
	get_root().add_child(parent)
	await process_frame
	poi.manifest = {"format": "fixture"}
	poi.refresh_accum = 0.0
	var avg := _measure("poi_far_idle", Callable(poi, "_process").bind(0.0), 2000)
	parent.queue_free()
	await process_frame
	return avg

func _bench_city_lights() -> float:
	var lights = CityLightsScript.new()
	lights.name = "CityLightsFixture"
	lights.process_mode = Node.PROCESS_MODE_DISABLED
	get_root().add_child(lights)
	await process_frame
	var avg := _measure("city_lights_visibility", Callable(lights, "_process").bind(0.0), 5000)
	lights.queue_free()
	await process_frame
	return avg

func _bench_debug_overlay() -> float:
	var main := DummyMain.new()
	main.name = "DebugFixture"
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var rig := DummyCameraRig.new()
	rig.name = "CameraRig"
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	main.add_child(rig)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	var label := Label.new()
	label.name = "Label"
	panel.add_child(label)
	var overlay = DebugOverlayScript.new()
	overlay.name = "DebugOverlay"
	overlay.add_child(panel)
	main.add_child(overlay)
	get_root().add_child(main)
	await process_frame
	# Avoid one-second log flushing; this benchmark is the every-frame overlay path.
	overlay.sample_time = 0.0
	var avg := _measure("debug_overlay", Callable(overlay, "_process").bind(0.0), 1000)
	main.queue_free()
	await process_frame
	return avg

func _bench_clouds() -> float:
	var clouds = CloudScript.new()
	clouds.name = "CloudFixture"
	clouds.process_mode = Node.PROCESS_MODE_DISABLED
	get_root().add_child(clouds)
	await process_frame
	clouds.set_view_state(Vector3.ZERO, 760000.0, Vector3(0.0, 760000.0, 0.0))
	var stats: Dictionary = clouds.get_render_stats()
	print("FRAME_DIAG cloud_puffs=%d clouds=%d lod=%d" % [int(stats.get("puff_instance_count", 0)), int(stats.get("cloud_count", 0)), int(stats.get("lod", -1))])
	var avg := _measure("cloud_update", Callable(clouds, "_process").bind(1.0 / 60.0), 30)
	clouds.queue_free()
	await process_frame
	return avg

func _measure(name: String, callable: Callable, iterations: int) -> float:
	for _warmup in range(3):
		callable.call()
	var started := Time.get_ticks_usec()
	for _index in range(iterations):
		callable.call()
	var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var average_ms := elapsed_ms / float(iterations)
	print("FRAME_DIAG %s iterations=%d total_ms=%.3f avg_ms=%.6f" % [name, iterations, elapsed_ms, average_ms])
	_assert(is_finite(average_ms) and average_ms >= 0.0, "%s timing is finite" % name)
	return average_ms

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("runtime frame-cost diagnostic failed: " + message)
