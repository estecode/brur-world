extends "res://harness/world_showcase/world_showcase.gd"

## Adapts the #126 showcase to a self-contained exported Windows test folder.
##
## Dependencies:
## - Reuses the normal world_showcase.gd behavior and production modules.
## - Reads only disposable runtime_data placed beside the exported executable.
## - Adds benchmark logging without changing production world ownership.

const BenchmarkLoggerScript = preload("res://harness/world_showcase/benchmark_logger.gd")
const WINDOWS_RUNTIME_DIR := "runtime_data"

func _runtime_cache_dir() -> String:
	return OS.get_executable_path().get_base_dir().path_join(WINDOWS_RUNTIME_DIR)

func _initialize() -> void:
	_coordinates = _main.call("get_world_coordinates")
	_configure_camera_for_continuous_scale()
	_disable_non_showcase_work()
	_buildings.active_radius_tiles = 0
	_buildings.builds_per_frame = 1
	_buildings.build_budget_ms = 3.5
	_buildings.max_pending_tiles = 4
	_buildings.prefetch_tiles_ahead = 0
	_buildings.appear_altitude_m = 16000.0
	_buildings.hide_altitude_m = 17500.0
	_buildings.full_height_altitude_m = 1800.0
	_buildings.base_height_m = 24.0
	_buildings.call("setup", _coordinates, _camera_rig, _runtime_cache_dir())
	_atmosphere.call("setup", _world_environment, _astronomical_sun, _camera_rig)
	_jump_to_city("Malmö", START_ALTITUDE_M)
	_spawn_player()
	_install_benchmark_logger()
	_update_controls()
	_update_status()

func _local_background_path(city: String) -> String:
	return "%s/background_%s.brmap" % [_runtime_cache_dir(), String(CITY_SLUG.get(city, "malmo"))]

func _install_benchmark_logger() -> void:
	var logger := BenchmarkLoggerScript.new()
	logger.name = "BenchmarkLogger"
	add_child(logger)
	logger.call("setup", _camera_rig, _buildings)

func _update_status() -> void:
	if _status == null or _camera_rig == null:
		return
	var driving := bool(_camera_rig.call("is_driving_view"))
	var altitude := float(_camera_rig.call("get_altitude"))
	var snapshot: Dictionary = _buildings.call("debug_snapshot") if _buildings != null else {}
	var atmosphere: Dictionary = _atmosphere.call("debug_profile") if _atmosphere != null else {}
	var cache_ready := FileAccess.file_exists(_runtime_cache_dir().path_join("showcase_manifest.json"))
	_status.text = "%s — Windows benchmark build\nScale: %s   Altitude: %.0f m   FPS: %d\nBuildings: %d active / %d pending / %d wanted   Records: %d\nBuild max: %.2f ms   Dropped: %d   Fog: %.6f\nCenter tile: %s   Data: %s\nLog: saved beside this EXE when the app closes" % [
		_current_city,
		_scale_label(altitude, driving),
		altitude,
		Engine.get_frames_per_second(),
		int(snapshot.get("active_tiles", 0)),
		int(snapshot.get("pending_tiles", 0)),
		int(snapshot.get("wanted_tiles", 0)),
		int(snapshot.get("active_records", 0)),
		float(_last_metrics.get("building_build_max_ms", 0.0)),
		int(_last_metrics.get("building_dropped_requests", 0)),
		float(atmosphere.get("fog_density", 0.0)),
		String(snapshot.get("last_center_tile", "")),
		"local runtime map + buildings" if cache_ready else "MISSING runtime_data",
	]
