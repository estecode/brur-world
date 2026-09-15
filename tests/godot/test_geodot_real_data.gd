extends SceneTree

## Real-data GeoDot smoke/performance check against the configured Sweden GeoPackage.
## Requires BRUR_GEODOT_GPKG and the pinned GeoDot addon installed by tools/setup_geodot_poc.sh.

const SourceScript = preload("res://scripts/geodot_world_source.gd")
const MeshBuilderScript = preload("res://scripts/geodot_world_mesh_builder.gd")
const WorldCoordinatesScript = preload("res://scripts/world_coordinates.gd")
const LUND_FOCUS := Vector3(-489086.0, 0.0, 1582123.0)
const CELL_SIZE := 2000.0
const MAX_BUILDING_SOURCE_FEATURES := 12000
const MAX_ROAD_SOURCE_FEATURES := 8000
const MACOS_TEARDOWN_ABORT_EXIT := 134

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var gpkg := OS.get_environment("BRUR_GEODOT_GPKG")
	_assert(not gpkg.is_empty(), "BRUR_GEODOT_GPKG is configured")
	if gpkg.is_empty():
		quit(1)
		return
	var manifest_path := "res://world_data/manifest.json"
	_assert(FileAccess.file_exists(manifest_path), "production world manifest exists")
	if not FileAccess.file_exists(manifest_path):
		quit(1)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	var coordinates = WorldCoordinatesScript.new(Vector2(float(manifest.get("origin_x", 0.0)), float(manifest.get("origin_y", 0.0))), float(manifest.get("tile_size", 32000.0)))
	var lund_abs: Vector2 = coordinates.world_to_absolute(LUND_FOCUS)
	var cell := Vector2i(floori(lund_abs.x / CELL_SIZE), floori(lund_abs.y / CELL_SIZE))
	var top_left := Vector2(float(cell.x) * CELL_SIZE, float(cell.y + 1) * CELL_SIZE)

	var source = SourceScript.new()
	var opened: Dictionary = source.open_dataset(gpkg)
	_assert(opened.get("ok", false) == true, "GeoDot opens production GeoPackage and resolves road/building layers")
	if opened.get("ok", false) != true:
		print("GeoDot open result: ", opened)
		quit(1)
		return
	_assert(int(opened.get("epsg", 0)) > 0, "GeoPackage feature CRS is explicit")
	var result: Dictionary = source.query_cell(top_left, CELL_SIZE, MAX_BUILDING_SOURCE_FEATURES, MAX_ROAD_SOURCE_FEATURES)
	_assert(result.get("ok", false) == true, "Lund cell query succeeds")
	_assert(int(result.get("building_features", 0)) > 0, "Lund query contains buildings")
	_assert(int(result.get("road_features", 0)) > 0, "Lund query contains roads")
	_assert(int(result.get("raw_building_features", 0)) < MAX_BUILDING_SOURCE_FEATURES, "Lund mixed polygon source query does not saturate before building filtering")
	_assert(int(result.get("raw_road_features", 0)) < MAX_ROAD_SOURCE_FEATURES, "Lund mixed line source query does not saturate before highway filtering")
	var build_started := Time.get_ticks_usec()
	var building_mesh := MeshBuilderScript.build_buildings(result.get("buildings", []), Vector2(float(cell.x) * CELL_SIZE, float(cell.y) * CELL_SIZE), MeshBuilderScript.LOD_FAR)
	var road_mesh := MeshBuilderScript.build_roads(result.get("roads", []), Vector2(float(cell.x) * CELL_SIZE, float(cell.y) * CELL_SIZE), MeshBuilderScript.LOD_FAR)
	var build_ms := float(Time.get_ticks_usec() - build_started) / 1000.0
	_assert(building_mesh != null, "real Lund buildings batch into a mesh")
	_assert(road_mesh != null, "real Lund roads batch into a mesh")
	_assert(int(result.get("building_features", 0)) <= MAX_BUILDING_SOURCE_FEATURES and int(result.get("road_features", 0)) <= MAX_ROAD_SOURCE_FEATURES, "feature query is explicitly bounded")
	print("GEODOT_REAL_DATA metadata=", opened)
	print("GEODOT_REAL_DATA lund_abs=", lund_abs, " cell=", cell, " buildings=", result.get("building_features"), " roads=", result.get("road_features"), " raw_buildings=", result.get("raw_building_features"), " raw_roads=", result.get("raw_road_features"), " building_query_ms=", result.get("building_query_ms"), " road_query_ms=", result.get("road_query_ms"), " build_ms=", build_ms)
	if _failed:
		quit(1)
		return
	if gpkg.get_file() == "sweden-brur.gpkg":
		_run_production_ab_performance()
	if _failed:
		quit(1)
		return
	print("geodot real-data test: OK")
	quit(0)

func _run_production_ab_performance() -> void:
	print("GEODOT_AB_PERF starting comparable production Drive measurements")
	if not _run_child_test("res://tests/godot/test_production_fps_real_data.gd", "production Drive FPS real-data test: OK", "legacy"):
		return
	_run_child_test("res://tests/godot/test_geodot_fps_real_data.gd", "GeoDot Drive FPS real-data test: OK", "geodot")

func _run_child_test(script: String, marker: String, label: String) -> bool:
	var output: Array = []
	var args := PackedStringArray([
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--script", script,
	])
	var exit_code := OS.execute(OS.get_executable_path(), args, output, true)
	var combined := ""
	for line in output:
		var text := String(line)
		combined += text + "\n"
		print(text)
	var completed := marker in combined
	# Godot 4.7.2 on macOS can abort in renderer/extension teardown after the
	# GeoDot child has printed its success marker. The marker is emitted only after
	# every runtime assertion and performance gate has passed, so this exact
	# post-marker abort is not a failed runtime test. Any earlier/non-marker abort
	# remains a hard failure.
	var known_post_marker_teardown_abort := OS.get_name() == "macOS" and exit_code == MACOS_TEARDOWN_ABORT_EXIT and completed
	if exit_code != 0 and not known_post_marker_teardown_abort:
		_assert(false, "%s performance child exited with %d" % [label, exit_code])
		return false
	if not completed:
		_assert(false, "%s performance child exited without completion marker" % label)
		return false
	if known_post_marker_teardown_abort:
		print("GEODOT_AB_PERF %s=OK teardown_abort_ignored=true exit=%d" % [label, exit_code])
	else:
		print("GEODOT_AB_PERF %s=OK" % label)
	return true

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("ASSERT FAILED: " + message)
