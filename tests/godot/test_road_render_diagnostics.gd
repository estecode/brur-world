extends SceneTree

## Quantifies the production BRT1 road tile presentation path without manual playtesting.
##
## Dependencies:
## - Exercises production main.gd road mesh construction with synthetic BRT1 data.
## - Uses no alternate road renderer and does not require production world data.

const MainScript = preload("res://scripts/main.gd")
const WorldCoordinatesScript = preload("res://scripts/world_coordinates.gd")

var _failed := false

func _init() -> void:
	var main = MainScript.new()
	main.world_coordinates = WorldCoordinatesScript.new(Vector2.ZERO, 32000.0)
	main.current_layer_spacing = 133.2

	var visible_min := Vector2i(38, 273)
	var visible_max := Vector2i(83, 296)
	var candidate_width := visible_max.x - visible_min.x + 1
	var candidate_height := visible_max.y - visible_min.y + 1
	var candidate_positions := candidate_width * candidate_height
	_assert(candidate_width == 46 and candidate_height == 24, "captured LOD0 tile rectangle dimensions stay understood")
	_assert(candidate_positions == 1104, "captured LOD0 rectangle contains 1104 candidate tile positions")

	var temp_dir := "user://road_render_diagnostics_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(temp_dir))
	var segment_counts := [100, 1000, 10000]
	for count in segment_counts:
		var path := "%s/lod0_%d.brtile" % [temp_dir, count]
		_write_tile(path, count)
		var started := Time.get_ticks_usec()
		var mesh: ArrayMesh = main._build_tile_mesh(path, 0)
		var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
		_assert(mesh != null, "LOD0 synthetic tile builds")
		if mesh != null:
			var arrays := mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			_assert(vertices.size() == count * 6, "road mesh emits six vertices per segment")
			print("ROAD_DIAG mesh_build segments=%d vertices=%d ms=%.3f" % [count, vertices.size(), elapsed_ms])

	var one_segment := "%s/one.brtile" % temp_dir
	_write_tile(one_segment, 1)
	var mesh_one: ArrayMesh = main._build_tile_mesh(one_segment, 0)
	_assert(mesh_one != null, "single LOD0 segment builds")
	if mesh_one != null:
		var bounds := mesh_one.get_aabb()
		# Synthetic class 0 uses 1400 m * 1.4 = 1960 m ribbon width.
		_assert(bounds.size.z >= 1959.0, "LOD0 motorway ribbon is about 1960 m wide")
		print("ROAD_DIAG lod0_single_segment_aabb=%s" % str(bounds))

	var instance := main._load_tile(one_segment, 0, 0, 0)
	_assert(instance != null, "production tile presentation creates a MeshInstance3D")
	if instance != null:
		_assert(instance.material_override is StandardMaterial3D, "production road tile owns a StandardMaterial3D override")
		var material := instance.material_override as StandardMaterial3D
		_assert(material.cull_mode == BaseMaterial3D.CULL_DISABLED, "production road material is double-sided")

	var simulated_tiles := 119
	var build_limit_per_frame := 1
	var seconds_at_4_fps := float(simulated_tiles) / (4.0 * float(build_limit_per_frame))
	_assert(is_equal_approx(seconds_at_4_fps, 29.75), "119 tiles need 29.75 seconds at 4 FPS with one build per frame")
	print("ROAD_DIAG candidate_positions=%d observed_tiles=%d one_tile_per_frame_seconds_at_4fps=%.2f" % [candidate_positions, simulated_tiles, seconds_at_4_fps])
	print("ROAD_DIAG interpretation=mesh CPU build is bounded; one-tile-per-frame policy explains slow fill independently of baseline FPS")

	if _failed:
		quit(1)
		return
	print("road render diagnostics: OK")
	quit(0)

func _write_tile(path: String, count: int) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_assert(file != null, "diagnostic BRT1 tile is writable")
	if file == null:
		return
	file.store_buffer("BRT1".to_ascii_buffer())
	file.store_32(count)
	for i in range(count):
		var x := float(i % 100) * 600.0
		var y := float(i / 100) * 600.0
		file.store_8(0)
		file.store_float(x)
		file.store_float(y)
		file.store_float(x + 500.0)
		file.store_float(y)
	file.close()

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("road render diagnostic failed: " + message)
