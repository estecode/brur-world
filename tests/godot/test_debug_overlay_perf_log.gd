extends SceneTree

## Headless regression test for debug overlay performance-log formatting.
##
## Dependencies:
## - Uses the production debug_overlay.gd implementation directly.
## - Writes only to a temporary user:// log file and does not depend on world/runtime data.

const DebugOverlayScript = preload("res://scripts/debug_overlay.gd")
const LOG_PATH := "user://debug_overlay_perf_log_test.log"

func _init() -> void:
	var overlay: CanvasLayer = DebugOverlayScript.new()
	var camera := Camera3D.new()
	camera.near = 0.25
	camera.far = 25000.0
	camera.fov = 60.0
	overlay.set("camera", camera)
	overlay.set("build_id", "test-build")
	overlay.set("shown_avg_ms", 17.0)
	overlay.set("shown_worst_ms", 40.0)
	overlay.set("shown_road_build_ms", 1.0)
	overlay.set("shown_road_build_max_ms", 2.0)
	overlay.set("shown_road_tiles_built", 3)
	overlay.set("shown_road_pending", 4)
	overlay.set("shown_road_refresh_ms", 5.0)
	overlay.set("shown_cache_hits", 6)
	overlay.set("shown_cache_misses", 7)
	overlay.set("shown_gps_queries", 8)
	overlay.set("shown_gps_route_ms", 12.25)
	overlay.set("shown_gps_route_max_ms", 34.5)
	overlay.set("shown_gps_settled", 9)
	overlay.set("shown_gps_relaxed", 10)
	overlay.set("shown_gps_parse_ms", 1.5)
	overlay.set("shown_gps_apply_ms", 2.5)
	overlay.set("shown_gps_points", 11)
	overlay.set("shown_gps_failures", 1)
	overlay.set("shown_gps_failure_reason", "timeout, retry")
	overlay.set("shown_gps_failed_leg", 2)
	overlay.set("shown_gps_busy", true)

	var log := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	_assert(log != null, "temporary performance log opens")
	overlay.set("perf_log", log)
	overlay.call("_write_perf_sample", 60.0, 1000.0, 2, 3, 4, 5, 6, 7, 8, 9)
	log.close()

	var reader := FileAccess.open(LOG_PATH, FileAccess.READ)
	_assert(reader != null, "temporary performance log can be read")
	var content := reader.get_as_text()
	reader.close()

	_assert(content.contains("PERF SPIKE,"), "spike line is written")
	_assert(content.contains("gps_route_ms=12.250"), "spike line includes current GPS route time")
	_assert(content.contains("gps_route_max_ms=34.500"), "spike line includes max GPS route time")
	_assert(content.contains("gps_failure_reason=timeout; retry"), "spike line keeps later fields aligned and CSV-safe")
	_assert(content.contains("gps_failed_leg=2"), "spike line keeps failed-leg field aligned")
	_assert(content.contains("gps_busy=true"), "spike line keeps busy field aligned")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG_PATH))
	overlay.free()
	camera.free()
	print("godot debug overlay performance log tests: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("Debug overlay performance log test failed: " + message)
	quit(1)
