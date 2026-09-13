extends SceneTree

## Verifies world-showcase appearance, background compositing, atmosphere, atomic building streaming, and camera-scale contracts.
## Dependencies: production map, building, atmosphere, coordinates, and camera modules only.

const MainScript = preload("res://scripts/main.gd")
const BuildingMeshBuilderScript = preload("res://scripts/building_mesh_builder.gd")
const BuildingStreamLayerScript = preload("res://scripts/building_stream_layer.gd")
const WorldCoordinatesScript = preload("res://scripts/world_coordinates.gd")
const WorldAtmosphereScript = preload("res://scripts/world_atmosphere.gd")
const CameraControllerScript = preload("res://scripts/camera_controller.gd")

var _failed := false

class DummyCameraRig:
	extends Node
	var focus := Vector3(10.0, 0.0, -10.0)
	var altitude := 4200.0
	func get_focus_world() -> Vector3:
		return focus
	func get_altitude() -> float:
		return altitude
	func get_ground_view_corners() -> PackedVector3Array:
		return PackedVector3Array([
			focus + Vector3(-2000.0, 0.0, -2000.0),
			focus + Vector3(2000.0, 0.0, -2000.0),
			focus + Vector3(2000.0, 0.0, 2000.0),
			focus + Vector3(-2000.0, 0.0, 2000.0),
		])

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_deterministic_building_appearance()
	_test_background_compositing()
	_test_atmosphere_profile()
	await _test_showcase_streaming_bounds()
	await process_frame
	_test_camera_scale_transition()
	if _failed:
		quit(1)
		return
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
	_assert(mesh != null and mesh.get_surface_count() == 1, "multiple buildings remain one batched reference surface")
	if mesh == null:
		return
	var arrays := mesh.surface_get_arrays(0)
	var vertex_colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	_assert(not vertex_colors.is_empty(), "batched reference mesh carries deterministic vertex colors")

func _test_background_compositing() -> void:
	var main = MainScript.new()
	var ocean: StandardMaterial3D = main._background_material(MainScript.MAP_WATER, true)
	var land: StandardMaterial3D = main._background_material(MainScript.MAP_LAND)
	var water: StandardMaterial3D = main._background_material(MainScript.MAP_WATER)
	var farmland: StandardMaterial3D = main._background_material(MainScript.MAP_FARMLAND)
	var forest: StandardMaterial3D = main._background_material(MainScript.MAP_FOREST)
	var urban: StandardMaterial3D = main._background_material(MainScript.MAP_URBAN)
	var layers: Array[StandardMaterial3D] = [ocean, land, water, farmland, forest, urban]
	for material in layers:
		_assert(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "background layers use the ordered transparent pass")
		_assert(material.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED, "background layers never compete by writing depth")
		_assert(not material.no_depth_test, "background layers still respect opaque road/building depth")
	_assert(ocean.render_priority < land.render_priority, "ocean renders before country land")
	_assert(land.render_priority < water.render_priority, "inland water renders above land")
	_assert(water.render_priority < farmland.render_priority, "farmland renders above broad water")
	_assert(farmland.render_priority < forest.render_priority, "forest renders above farmland")
	_assert(forest.render_priority < urban.render_priority, "urban renders last among background classes")
	main._setup_road_material()
	_assert(main.road_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "roads remain opaque")
	_assert(main.road_material.depth_draw_mode != BaseMaterial3D.DEPTH_DRAW_DISABLED, "roads keep depth writes for foreground occlusion")

func _test_atmosphere_profile() -> void:
	var high: Dictionary = WorldAtmosphereScript.profile_for_altitude(30000.0)
	var city: Dictionary = WorldAtmosphereScript.profile_for_altitude(9000.0)
	var low: Dictionary = WorldAtmosphereScript.profile_for_altitude(3500.0)
	_assert(is_equal_approx(float(high["fog_density"]), 0.0), "high map view keeps haze effectively off")
	_assert(float(city["fog_density"]) > float(high["fog_density"]), "haze grows gradually during city descent")
	_assert(float(low["fog_density"]) > float(city["fog_density"]), "street approach has stronger depth haze")

func _test_showcase_streaming_bounds() -> void:
	var cache_dir := "user://world_showcase_test_%d" % Time.get_ticks_usec()
	_write_bmc_chunk(cache_dir, 1, Vector2i(0, 0))
	_write_bmc_chunk(cache_dir, 0, Vector2i(0, 0))
	var coordinates = WorldCoordinatesScript.new(Vector2.ZERO, 2000.0)
	var camera := DummyCameraRig.new()
	get_root().add_child(camera)
	var layer := BuildingStreamLayerScript.new()
	layer.view_margin_chunks = 0
	layer.max_view_chunks = 16
	layer.max_cache_chunks = 4
	layer.appear_altitude_m = 16000.0
	layer.hide_altitude_m = 17500.0
	layer.streaming_enabled = false
	get_root().add_child(layer)
	layer.setup(coordinates, camera, cache_dir)
	layer.set_streaming_enabled(true)
	await _wait_until_ready(layer)
	_assert(layer.active_mesh_count() == 1, "showcase publishes one coherent building viewport mesh")
	var active_instance: MeshInstance3D = layer._active_instance
	_assert(active_instance != null and active_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "showcase building viewport does not cast expensive dynamic shadows by default")

	camera.altitude = 16800.0
	layer._process(0.0)
	await _wait_until_ready(layer)
	_assert(layer.active_mesh_count() == 1, "showcase keeps an eligible coherent viewport through visibility hysteresis")
	camera.altitude = 17600.0
	layer._process(0.0)
	_assert(layer.active_mesh_count() == 0, "showcase unloads above hide threshold")

	camera.altitude = 4200.0
	camera.focus = Vector3(90000.0, 0.0, 0.0)
	layer._process(0.0)
	await _wait_until_ready(layer)
	_assert(layer.active_mesh_count() == 0, "empty distant viewport atomically replaces stale city geometry")
	layer.queue_free()
	camera.queue_free()
	await process_frame

func _wait_until_ready(layer: Node) -> void:
	for _index in range(120):
		layer._process(0.0)
		if layer.is_viewport_ready():
			return
		await process_frame
	_assert(false, "showcase building viewport stages within bounded test frames")

func _test_camera_scale_transition() -> void:
	var rig = CameraControllerScript.new()
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	get_root().add_child(rig)
	rig.overview_pitch_degrees = 84.0
	rig.gameplay_pitch_degrees = 36.0
	rig.gameplay_blend_start_altitude_m = 30000.0
	if rig.altitude_model == null:
		rig._ready()
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

func _write_bmc_chunk(root_dir: String, lod: int, chunk: Vector2i) -> void:
	var directory := "%s/lod%d" % [root_dir, lod]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file := FileAccess.open("%s/%d_%d.bmc" % [directory, chunk.x, chunk.y], FileAccess.WRITE)
	_assert(file != null, "showcase prebuilt chunk is writable")
	if file == null:
		return
	file.store_buffer("BMC2".to_ascii_buffer())
	file.store_32(2)
	file.store_32(3)
	file.store_float(0.0)
	file.store_float(0.0)
	file.store_32(3)
	for position in [Vector3(0.0, 0.0, 0.0), Vector3(100.0, 0.0, 0.0), Vector3(0.0, 20.0, -100.0)]:
		file.store_float(position.x)
		file.store_float(position.y)
		file.store_float(position.z)
		file.store_float(0.0)
		file.store_float(1.0)
		file.store_float(0.0)
		file.store_8(130)
		file.store_8(134)
		file.store_8(138)
		file.store_8(255)
	file.close()

func _record(x: float, y: float, source_id: String, size_m: float = 10.0) -> Dictionary:
	var half := size_m * 0.5
	return {"id": source_id, "x": x, "y": y, "geometry": [{"outer": [[x - half, y - half], [x + half, y - half], [x + half, y + half], [x - half, y + half]], "holes": []}], "tags": {"building": "yes", "building:levels": "4"}}

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("world showcase test failed: " + message)
