extends SceneTree

## Benchmarks production RoadSurfaceQuery against local Sweden BRT1 runtime data.
## Dependencies: production RoadSurfaceQuery, WorldCoordinates, and local world_data linked by PR check.

const RoadSurfaceQueryScript = preload("res://scripts/road_surface_query.gd")
const WorldCoordinatesScript = preload("res://scripts/world_coordinates.gd")
const WORLD_DIR := "res://world_data"
const STOCKHOLM_ABSOLUTE := Vector2(2013000.0, 8251000.0)
const WARM_QUERIES := 240
const MAX_WARM_AVG_MS := 8.0
const MAX_SEGMENTS_PER_QUERY := 500.0

func _init() -> void:
	var manifest_path := WORLD_DIR + "/manifest.json"
	if not FileAccess.file_exists(manifest_path):
		push_error("road-surface real-data test failed: missing manifest")
		quit(1)
		return
	var manifest_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if typeof(manifest_value) != TYPE_DICTIONARY:
		push_error("road-surface real-data test failed: invalid manifest")
		quit(1)
		return
	var manifest := manifest_value as Dictionary
	var coordinates = WorldCoordinatesScript.new(
		Vector2(float(manifest.get("origin_x", 0.0)), float(manifest.get("origin_y", 0.0))),
		float(manifest.get("tile_size", 32000.0))
	)
	var query = RoadSurfaceQueryScript.new()
	query.setup(WORLD_DIR, coordinates)

	var cold_started := Time.get_ticks_usec()
	query.surface_at(coordinates.absolute_to_world(STOCKHOLM_ABSOLUTE))
	var cold_ms := float(Time.get_ticks_usec() - cold_started) / 1000.0
	query.consume_perf_metrics()

	var warm_started := Time.get_ticks_usec()
	for index in range(WARM_QUERIES):
		var offset := Vector2(float((index % 16) - 8) * 6.0, float((index / 16) - 7) * 6.0)
		query.surface_at(coordinates.absolute_to_world(STOCKHOLM_ABSOLUTE + offset))
	var warm_total_ms := float(Time.get_ticks_usec() - warm_started) / 1000.0
	var metrics: Dictionary = query.consume_perf_metrics()
	var warm_avg_ms := warm_total_ms / float(WARM_QUERIES)
	var segments_per_query := float(metrics.get("segments_checked", 0)) / float(maxi(1, int(metrics.get("queries", 0))))
	print("ROAD_SURFACE_REAL_DATA cold_ms=%.3f warm_avg_ms=%.4f segments_per_query=%.2f queries=%d" % [
		cold_ms, warm_avg_ms, segments_per_query, WARM_QUERIES
	])
	if warm_avg_ms > MAX_WARM_AVG_MS:
		push_error("road-surface real-data test failed: warm average %.3f ms exceeds %.1f ms" % [warm_avg_ms, MAX_WARM_AVG_MS])
		quit(1)
		return
	if segments_per_query > MAX_SEGMENTS_PER_QUERY:
		push_error("road-surface real-data test failed: %.1f candidate segments/query exceeds %.1f" % [segments_per_query, MAX_SEGMENTS_PER_QUERY])
		quit(1)
		return
	print("road surface real-data tests: OK")
	quit(0)
