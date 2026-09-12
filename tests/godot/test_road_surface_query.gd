extends SceneTree

## Verifies road/off-road classification and bounded candidate scans in RoadSurfaceQuery.
## Dependencies: production RoadSurfaceQuery, WorldCoordinates, and synthetic BRT1 fixture tiles.

const RoadSurfaceQueryScript = preload("res://scripts/road_surface_query.gd")
const WorldCoordinatesScript = preload("res://scripts/world_coordinates.gd")

var _failed := false
var _root_dir := ""

func _init() -> void:
	_root_dir = "user://road_surface_query_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_root_dir + "/lod2"))
	_test_classification_and_bin_boundary()
	_test_dense_tile_candidate_reduction()
	_test_long_diagonal_index_is_linear()
	if _failed:
		quit(1)
		return
	print("road surface query tests: OK")
	quit(0)

func _test_classification_and_bin_boundary() -> void:
	_write_tile(Vector2i(0, 0), [
		{"class": 0, "a": Vector2(120.0, 100.0), "b": Vector2(140.0, 100.0)},
	])
	var coordinates = WorldCoordinatesScript.new(Vector2.ZERO, 32000.0)
	var query = RoadSurfaceQueryScript.new()
	query.setup(_root_dir, coordinates)
	_assert(query.surface_at(coordinates.absolute_to_world(Vector2(128.0, 104.0))) == &"road", "road stays detectable across a spatial-bin boundary")
	_assert(query.surface_at(coordinates.absolute_to_world(Vector2(128.0, 108.5))) == &"off_road", "road width semantics stay unchanged outside the half-width")

func _test_dense_tile_candidate_reduction() -> void:
	var segments: Array[Dictionary] = []
	for row in range(50):
		for column in range(40):
			var x := 400.0 + float(column) * 500.0
			var y := 400.0 + float(row) * 500.0
			segments.append({"class": 6, "a": Vector2(x, y), "b": Vector2(x + 80.0, y)})
	_write_tile(Vector2i(1, 0), segments)
	var coordinates = WorldCoordinatesScript.new(Vector2.ZERO, 32000.0)
	var query = RoadSurfaceQueryScript.new()
	query.setup(_root_dir, coordinates)
	var probe_absolute := Vector2(32450.0, 460.0)
	query.surface_at(coordinates.absolute_to_world(probe_absolute))
	var metrics: Dictionary = query.consume_perf_metrics()
	_assert(int(metrics["queries"]) == 1, "performance metrics count one surface query")
	_assert(int(metrics["segments_checked"]) < 50, "dense tile query checks only local spatial candidates")

func _test_long_diagonal_index_is_linear() -> void:
	# Keep this fixture outside the 3x3 neighborhood of the dense-tile fixture so
	# index-entry accounting measures only the long segment under test.
	_write_tile(Vector2i(4, 0), [
		{"class": 0, "a": Vector2(100.0, 100.0), "b": Vector2(30000.0, 30000.0)},
	])
	var coordinates = WorldCoordinatesScript.new(Vector2.ZERO, 32000.0)
	var query = RoadSurfaceQueryScript.new()
	query.setup(_root_dir, coordinates)
	var probe_absolute := Vector2(128100.0, 100.0)
	query.surface_at(coordinates.absolute_to_world(probe_absolute))
	var metrics: Dictionary = query.consume_perf_metrics()
	_assert(int(metrics["index_entries"]) < 10000, "long diagonal indexing grows with segment length instead of its full AABB area")

func _write_tile(tile: Vector2i, segments: Array[Dictionary]) -> void:
	var path := "%s/lod2/%d_%d.brtile" % [_root_dir, tile.x, tile.y]
	var file := FileAccess.open(path, FileAccess.WRITE)
	_assert(file != null, "BRT1 fixture tile is writable")
	if file == null:
		return
	file.store_buffer("BRT1".to_ascii_buffer())
	file.store_32(segments.size())
	for segment in segments:
		file.store_8(int(segment["class"]))
		var a: Vector2 = segment["a"] as Vector2
		var b: Vector2 = segment["b"] as Vector2
		file.store_float(a.x)
		file.store_float(a.y)
		file.store_float(b.x)
		file.store_float(b.y)
	file.close()

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("road-surface-query test failed: " + message)
