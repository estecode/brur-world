extends SceneTree

## Verifies #126 deterministic appearance, atmosphere, streaming, and camera-scale contracts.
## Dependencies: production building, atmosphere, coordinates, and camera modules only.

const BuildingMeshBuilderScript = preload("res://scripts/building_mesh_builder.gd")
const BuildingStreamLayerScript = preload("res://scripts/building_stream_layer.gd")
const WorldCoordinatesScript = preload("res://scripts/world_coordinates.gd")
const WorldAtmosphereScript = preload("res://scripts/world_atmosphere.gd")
const CameraControllerScript = preload("res://scripts/camera_controller.gd")

class DummyCameraRig:
	extends Node
	var focus := Vector3(10.0, 0.0, -10.0)
	var altitude := 4200.0
	func get_focus_world() -> Vector3:
		return focus
	func get_altitude() -> float:
		return altitude

func _init() -> void:
	_test_deterministic_building_appearance()
	_test_atmosphere_profile()
	_test_showcase_streaming_bounds()
	_test_camera_scale_transition()
	print("world showcase tests: OK")
	quit(0)

func _test_deterministic_building_appearance() -> void:
	var record_a := _record(10.0, 10.0, "way/alpha")
	var record_b := _record(30.0, 10.0, "way/beta")
	var colors_a: Dictionary = BuildingMeshBuilderScript.appearance_colors(record_a)
	var colors_a_reload: Dictionary = BuildingMeshBuilderScript.appearance_colors(record_a.duplicate(true))
	var colors_b: Dictionary = BuildingMeshBuilderScript.appearance_colors(record_b)
	var wall_a: Color = colors_a["wall"]
	var base_a: Color = colors_a["base"]
	var wall_b: Color = colors_b["wall"]
	_assert(colors_a == colors_a_reload, "building appearance survives unload/reload deterministically")
	_assert(wall_a != wall_b, "different stable IDs can produce restrained appearance variation")
	_assert(wall_a.r >= 0.42 and wall_a.r <= 0.56, "wall variation stays restrained")
	_assert(base_a.get_luminance() < wall_a.get_luminance(), "building base is darker for contact shading")
	var mesh: ArrayMesh = BuildingMeshBuilderScript.build_tile_mesh([record_a, record_b], Vector2.ZERO)
	_assert(mesh != null and mesh.get_surface_count() == 1, "multiple buildings remain one batched tile surface")
	var arrays := mesh.surface_get_arrays(0)
	var vertex_colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	_assert(not vertex_colors.is_empty(), "batched mesh carries deterministic vertex colors")
	var min_luma := 10.0
	var max_luma := -1.0
	for color in vertex_colors:
		min_luma = minf(min_luma, color.get_luminance())
		max_luma = maxf(max_luma, color.get_luminance())
	_assert(max_luma - min_luma > 0.04, "roof/wall/base shading remains visible inside one batch")

func _test_atmosphere_profile() -> void:
	var high: Dictionary = WorldAtmosphereScript.profile_for_altitude(30000.0)
	var city: Dictionary = WorldAtmosphereScript.profile_for_altitude(9000.0)
	var low: Dictionary = WorldAtmosphereScript.profile_for_altitude(3500.0)
	_assert(is_equal_approx(float(high["fog_density"]), 0.0), "high map view keeps haze effectively off")
	_assert(float(city["fog_density"]) > float(high["fog_density"]), "haze grows gradually during city descent")
	_assert(float(low["fog_density"]) > float(city["fog_density"]), "street approach has stronger depth haze")
	_assert(float(low["blend"]) <= 1.0 and float(low["blend"]) >= 0.99, "atmosphere blend is bounded")

func _test_showcase_streaming_bounds() -> void:
	var cache_dir := "user://world_showcase_test_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_dir))
	_write_tile(cache_dir, Vector2i(0, 0), _record(10.0, 10.0, "way/0"))
	_write_tile(cache_dir, Vector2i(1, 0), _record(110.0, 10.0, "way/1"))
	_write_tile(cache_dir, Vector2i(2, 0), _record(210.0, 10.0, "way/2"))

	var coordinates = WorldCoordinatesScript.new(Vector2.ZERO, 100.0)
	var camera := DummyCameraRig.new()
	get_root().add_child(camera)
	var layer := BuildingStreamLayerScript.new()
	layer.active_radius_tiles = 1
	layer.max_pending_tiles = 2
	layer.builds_per_frame = 1
	layer.build_budget_ms = 1000.0
	layer.prefetch_tiles_ahead = 0
	layer.appear_altitude_m = 16000.0
	layer.hide_altitude_m = 17500.0
	get_root().add_child(layer)
	layer.setup(coordinates, camera, cache_dir)
	_assert(layer.pending_tile_count() == 2, "showcase queue remains bounded")
	layer._process(0.0)
	_assert(layer.active_tile_count() == 1, "showcase builds at most one configured tile per frame")
	var first_instance: MeshInstance3D = layer._active.values()[0] as MeshInstance3D
	_assert(first_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "showcase building batches do not cast expensive dynamic shadows by default")
	camera.altitude = 16800.0
	layer._process(0.0)
	_assert(layer.active_tile_count() == 1, "showcase keeps geometry through visibility hysteresis")
	camera.altitude = 17600.0
	layer._process(0.0)
	_assert(layer.active_tile_count() == 0, "showcase unloads above hide threshold")
	camera.altitude = 4200.0
	camera.focus = Vector3(1010.0, 0.0, -10.0)
	layer._process(0.0)
	_assert(layer.active_tile_count() == 0 and layer.pending_tile_count() == 0, "large city jump leaves no stale geometry or queue")

func _test_camera_scale_transition() -> void:
	var rig = CameraControllerScript.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	get_root().add_child(rig)
	rig.overview_pitch_degrees = 84.0
	rig.gameplay_pitch_degrees = 36.0
	rig.gameplay_blend_start_altitude_m = 30000.0
	rig.set_altitude(30000.0)
	var high_pitch := rad_to_deg(float(rig._pitch_radians()))
	rig.set_altitude(1400.0)
	var low_pitch := rad_to_deg(float(rig._pitch_radians()))
	_assert(high_pitch > 80.0, "30 km view stays near top-down")
	_assert(low_pitch < 42.0, "street approach tilts into perspective")
	_assert(low_pitch < high_pitch, "camera pitch changes continuously in the intended direction")
	var dummy_target := Node3D.new()
	dummy_target.position = Vector3(12.0, 24.8, -20.0)
	get_root().add_child(dummy_target)
	rig.set_follow_target(dummy_target)
	rig.set_drive_mode(true)
	_assert(rig.is_driving_view(), "manual drive handoff enters production drive camera state")
	_assert(rig.is_mode_transition_active(), "manual drive handoff uses production smooth mode transition")

func _record(x: float, y: float, source_id: String) -> Dictionary:
	return {
		"id": source_id,
		"x": x,
		"y": y,
		"geometry": [{"outer": [[x - 5.0, y - 5.0], [x + 5.0, y - 5.0], [x + 5.0, y + 5.0], [x - 5.0, y + 5.0]], "holes": []}],
		"tags": {"building": "yes", "building:levels": "4"},
	}

func _write_tile(cache_dir: String, tile: Vector2i, record: Dictionary) -> void:
	var path := "%s/%d_%d.jsonl" % [cache_dir, tile.x, tile.y]
	var file := FileAccess.open(path, FileAccess.WRITE)
	_assert(file != null, "showcase test tile is writable")
	file.store_line(JSON.stringify(record))
	file.close()

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("world showcase test failed: " + message)
	quit(1)
