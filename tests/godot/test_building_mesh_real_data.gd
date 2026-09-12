extends SceneTree

## Benchmarks production building viewport staging against real Sweden-derived prebuilt mesh chunks.
## Dependencies: world_data manifest/building_mesh_lod, WorldCoordinates, and production BuildingStreamLayer.

const WorldCoordinatesScript = preload("res://scripts/world_coordinates.gd")
const BuildingStreamLayerScript = preload("res://scripts/building_stream_layer.gd")
const WORLD_DIR := "res://world_data"
const STOCKHOLM_ABSOLUTE := Vector2(2013000.0, 8251000.0)
const COLD_TARGET_MS := 750.0
const WARM_TARGET_MS := 250.0
const MAIN_THREAD_TARGET_MS := 5.0

var _failed := false

class DummyCameraRig:
	extends Node
	var focus := Vector3.ZERO
	var altitude := 6000.0
	var view_half_extent_m := 6000.0
	func get_focus_world() -> Vector3:
		return focus
	func get_altitude() -> float:
		return altitude
	func get_ground_view_corners() -> PackedVector3Array:
		return PackedVector3Array([
			focus + Vector3(-view_half_extent_m, 0.0, -view_half_extent_m),
			focus + Vector3(view_half_extent_m, 0.0, -view_half_extent_m),
			focus + Vector3(view_half_extent_m, 0.0, view_half_extent_m),
			focus + Vector3(-view_half_extent_m, 0.0, view_half_extent_m),
		])

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var manifest_path := WORLD_DIR + "/manifest.json"
	var mesh_dir := WORLD_DIR + "/building_mesh_lod"
	_assert(FileAccess.file_exists(manifest_path), "real-data manifest exists")
	_assert(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(mesh_dir)), "prebuilt building mesh LOD directory exists")
	if _failed:
		quit(1)
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	_assert(typeof(manifest) == TYPE_DICTIONARY, "real-data manifest parses")
	if _failed:
		quit(1)
		return
	var manifest_dict: Dictionary = manifest
	var coordinates = WorldCoordinatesScript.new(
		Vector2(float(manifest_dict.get("origin_x", 0.0)), float(manifest_dict.get("origin_y", 0.0))),
		2000.0
	)
	var camera := DummyCameraRig.new()
	camera.focus = coordinates.absolute_to_world(STOCKHOLM_ABSOLUTE)
	get_root().add_child(camera)
	var layer := BuildingStreamLayerScript.new()
	layer.view_margin_chunks = 1
	layer.max_view_chunks = 64
	layer.max_cache_chunks = 96
	layer.streaming_enabled = false
	get_root().add_child(layer)
	layer.setup(coordinates, camera, mesh_dir)

	var cold_started := Time.get_ticks_usec()
	layer.set_streaming_enabled(true)
	await _wait_ready(layer, 600)
	var cold_total_ms := float(Time.get_ticks_usec() - cold_started) / 1000.0
	var cold_metrics: Dictionary = layer.consume_perf_metrics()
	_assert(layer.is_viewport_ready(), "cold Stockholm viewport stages completely")
	_assert(layer.active_mesh_count() == 1, "cold viewport publishes one coherent mesh")
	_assert(cold_total_ms <= COLD_TARGET_MS, "cold local-SSD viewport meets %.0f ms target (%.1f ms)" % [COLD_TARGET_MS, cold_total_ms])
	_assert(float(cold_metrics["building_publish_max_ms"]) <= MAIN_THREAD_TARGET_MS, "atomic publish meets %.1f ms main-thread target (%.2f ms)" % [MAIN_THREAD_TARGET_MS, float(cold_metrics["building_publish_max_ms"])])

	# Prime an adjacent view, then return to Stockholm so the third request is warm-cache.
	camera.focus += Vector3(9000.0, 0.0, 0.0)
	layer._process(0.0)
	await _wait_ready(layer, 600)
	layer.consume_perf_metrics()
	camera.focus -= Vector3(9000.0, 0.0, 0.0)
	var warm_started := Time.get_ticks_usec()
	layer._process(0.0)
	await _wait_ready(layer, 600)
	var warm_total_ms := float(Time.get_ticks_usec() - warm_started) / 1000.0
	var warm_metrics: Dictionary = layer.consume_perf_metrics()
	_assert(warm_total_ms <= WARM_TARGET_MS, "warm-cache viewport meets %.0f ms target (%.1f ms)" % [WARM_TARGET_MS, warm_total_ms])
	_assert(int(warm_metrics["building_cache_hits"]) > 0, "warm return reuses decoded building chunks")
	_assert(float(warm_metrics["building_publish_max_ms"]) <= MAIN_THREAD_TARGET_MS, "warm atomic publish stays within main-thread frame budget")
	_assert(int(layer.debug_snapshot()["cache_chunks"]) <= layer.max_cache_chunks, "real-data chunk cache remains bounded")

	print(
		"building real-data performance: OK cold=%.1fms warm=%.1fms cold_stage=%.1fms warm_stage=%.1fms publish_max=%.2fms chunks=%d vertices=%d" % [
			cold_total_ms,
			warm_total_ms,
			float(cold_metrics["building_stage_max_ms"]),
			float(warm_metrics["building_stage_max_ms"]),
			maxf(float(cold_metrics["building_publish_max_ms"]), float(warm_metrics["building_publish_max_ms"])),
			int(layer.debug_snapshot()["active_chunks"]),
			int(layer.debug_snapshot()["active_vertices"]),
		]
	)
	layer.set_streaming_enabled(false)
	layer.queue_free()
	camera.queue_free()
	await process_frame
	quit(1 if _failed else 0)

func _wait_ready(layer: Node, max_frames: int) -> void:
	for _index in range(max_frames):
		layer._process(0.0)
		if layer.is_viewport_ready():
			return
		await process_frame
	_assert(false, "real-data building viewport staging completes in bounded time")

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("building real-data test failed: " + message)
