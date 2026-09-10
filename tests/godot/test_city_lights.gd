extends SceneTree

## Headless deterministic, POI-density, LOD, and production-composition tests for nighttime city lighting.
## Dependencies: production city-light model/renderer, day/night environment adapter, main scene.

const CityLightModelScript = preload("res://scripts/city_light_model.gd")
const CityLightRendererScript = preload("res://scripts/city_light_renderer.gd")
const DayNightEnvironmentAdapterScript = preload("res://scripts/day_night_environment_adapter.gd")
const MULTIMESH_3D_STRIDE: int = 12

class MockCameraRig:
	extends Node3D
	var distance_m := 5000.0
	func get_distance() -> float:
		return distance_m

class MockSunController:
	extends Node
	signal solar_state_changed(solar_state: Dictionary)
	var state := {"valid": true, "elevation_deg": -8.0}
	func get_last_solar_state() -> Dictionary:
		return state.duplicate(true)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var model = CityLightModelScript.new()
	_test_solar_intensity(model)
	_test_density_and_distribution(model)
	_test_budget_preserves_extent_and_irregularity()
	_test_poi_density_weighting()
	_test_production_composition()
	await _test_environment_contrast()
	await _test_renderer_visual_contracts()
	await _test_large_renderer_multimesh_distribution()
	print("godot city light tests: OK")
	quit(0)

func _test_solar_intensity(model) -> void:
	_assert(is_zero_approx(model.night_intensity(5.0)), "daylight disables city lighting")
	var dusk := float(model.night_intensity(-2.0))
	_assert(dusk > 0.0 and dusk < 1.0, "dusk fades instead of switching abruptly")
	_assert(is_equal_approx(float(model.night_intensity(-8.0)), 1.0), "deep night reaches full intensity")
	_assert(float(model.night_intensity(-4.0)) > dusk, "intensity rises monotonically after sunset")

func _test_density_and_distribution(model) -> void:
	for x in range(10):
		for z in range(10):
			var ox := float(x) * 450.0
			var oz := float(z) * 450.0
			model.add_urban_triangle(Vector3(ox + 20.0, 0.0, oz + 20.0), Vector3(ox + 400.0, 0.0, oz + 20.0), Vector3(ox + 20.0, 0.0, oz + 400.0))
	model.add_poi_density_sample(Vector3(2000.0, 0.0, 2000.0), 100)
	var overview: Array[Vector3] = model.overview_points()
	var local: Array[Vector3] = model.local_light_points()
	_assert(overview.size() > 100, "POI density strengthens overview glow beyond one cluster per urban cell")
	_assert(local.size() >= 800, "dense POI-backed urban field produces many small local lights")
	var first := local.duplicate()
	model.reset_distribution()
	for x in range(10):
		for z in range(10):
			var ox := float(x) * 450.0
			var oz := float(z) * 450.0
			model.add_urban_triangle(Vector3(ox + 20.0, 0.0, oz + 20.0), Vector3(ox + 400.0, 0.0, oz + 20.0), Vector3(ox + 20.0, 0.0, oz + 400.0))
	model.add_poi_density_sample(Vector3(2000.0, 0.0, 2000.0), 100)
	_assert(first == model.local_light_points(), "same urban geometry and POI density produce identical local lights")
	_assert(model.local_light_points(37).size() == 37, "distribution respects an explicit point budget")

func _test_budget_preserves_extent_and_irregularity() -> void:
	var model = CityLightModelScript.new()
	for x in range(40):
		for z in range(40):
			var ox := float(x) * 5000.0
			var oz := float(z) * 5000.0
			model.add_urban_triangle(Vector3(ox + 20.0, 0.0, oz + 20.0), Vector3(ox + 400.0, 0.0, oz + 20.0), Vector3(ox + 20.0, 0.0, oz + 400.0))
			if x < 5 and z < 5:
				model.add_poi_density_sample(Vector3(ox, 0.0, oz), 200)
	var points: Array[Vector3] = model.local_light_points(700)
	_assert(points.size() == 700, "budgeted distribution fills requested local-light budget")
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	var offsets: Dictionary = {}
	for point in points:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_z = minf(min_z, point.z)
		max_z = maxf(max_z, point.z)
		var key := "%d:%d" % [int(floor(fposmod(point.x, 450.0) / 25.0)), int(floor(fposmod(point.z, 450.0) / 25.0))]
		offsets[key] = true
	_assert((max_x - min_x) > 100000.0 and (max_z - min_z) > 100000.0, "budgeting preserves broad geographic spread instead of consuming dense cells first")
	_assert(offsets.size() >= 24, "deterministic offsets remain visibly irregular rather than collapsing onto a grid")

func _test_poi_density_weighting() -> void:
	var sparse = CityLightModelScript.new()
	var medium = CityLightModelScript.new()
	var dense = CityLightModelScript.new()
	for candidate in [sparse, medium, dense]:
		candidate.add_urban_triangle(Vector3(20.0, 0.0, 20.0), Vector3(400.0, 0.0, 20.0), Vector3(20.0, 0.0, 400.0))
	medium.add_poi_density_sample(Vector3(225.0, 0.0, 225.0), 4)
	dense.add_poi_density_sample(Vector3(225.0, 0.0, 225.0), 128)
	_assert(medium.local_light_points().size() > sparse.local_light_points().size(), "more POIs increase local light density")
	_assert(dense.local_light_points().size() > medium.local_light_points().size(), "POI weighting remains monotonic")
	_assert(dense.overview_points().size() > sparse.overview_points().size(), "more POIs strengthen overview glow")
	_assert(dense.density_weight_at(Vector3(225.0, 0.0, 225.0)) < 8.0, "POI weighting is logarithmic rather than linear")

func _test_production_composition() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	_assert(scene != null, "production main scene loads")
	var instance := scene.instantiate()
	var adapter := instance.get_node_or_null("DayNightEnvironment")
	_assert(adapter != null, "production scene includes day/night environment adapter")
	_assert(adapter.sun_controller_path == NodePath("../SunRuntimeController"), "adapter consumes production solar state")
	instance.free()
	var main_file := FileAccess.open("res://scripts/main.gd", FileAccess.READ)
	_assert(main_file != null, "production composition source is readable")
	if main_file != null:
		var source := main_file.get_as_text()
		_assert(source.contains("city_lights.begin_urban_data()"), "production feeds BRM2 urban data to city lights")
		_assert(source.contains("kind == MAP_URBAN"), "city lights derive from authoritative urban layer")
		_assert(source.contains("_load_city_light_poi_density()"), "production also consumes derived runtime POI density")
		_assert(source.contains("world_coordinates.absolute_to_world"), "POI density uses the shared coordinate conversion owner")

func _test_environment_contrast() -> void:
	var host := Node.new()
	root.add_child(host)
	var sun := MockSunController.new()
	sun.name = "Sun"
	host.add_child(sun)
	var world_environment := WorldEnvironment.new()
	world_environment.name = "Environment"
	world_environment.environment = Environment.new()
	world_environment.environment.background_mode = Environment.BG_COLOR
	world_environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	host.add_child(world_environment)
	var adapter = DayNightEnvironmentAdapterScript.new()
	adapter.sun_controller_path = NodePath("../Sun")
	adapter.world_environment_path = NodePath("../Environment")
	host.add_child(adapter)
	await process_frame
	adapter.apply_solar_state({"valid": true, "elevation_deg": 8.0})
	var day_energy := world_environment.environment.ambient_light_energy
	var day_background := world_environment.environment.background_color
	adapter.apply_solar_state({"valid": true, "elevation_deg": -8.0})
	var night_energy := world_environment.environment.ambient_light_energy
	var night_background := world_environment.environment.background_color
	_assert(night_energy < day_energy * 0.30, "night ambient remains substantially darker than day")
	_assert(night_background.get_luminance() < day_background.get_luminance() * 0.30, "night background remains dark")
	_assert(night_background.b > night_background.r, "night base remains dark blue rather than pure black")
	host.queue_free()
	await process_frame

func _test_renderer_visual_contracts() -> void:
	var camera := MockCameraRig.new()
	camera.name = "CameraRig"
	root.add_child(camera)
	var renderer = CityLightRendererScript.new()
	renderer.name = "CityLights"
	renderer.camera_rig_path = NodePath("../CameraRig")
	root.add_child(renderer)
	await process_frame
	renderer.begin_urban_data()
	for x in range(6):
		for z in range(6):
			var ox := float(x) * 450.0
			var oz := float(z) * 450.0
			renderer.add_urban_triangle(Vector3(ox + 20.0, 0.0, oz + 20.0), Vector3(ox + 400.0, 0.0, oz + 20.0), Vector3(ox + 20.0, 0.0, oz + 400.0))
	renderer.add_poi_density_sample(Vector3(1000.0, 0.0, 1000.0), 100)
	renderer.finish_urban_data()
	renderer.apply_solar_state({"valid": true, "elevation_deg": -8.0})
	await process_frame
	var stats: Dictionary = renderer.get_render_stats()
	_assert(int(stats["poi_density_total"]) == 100, "renderer forwards POI density into the production model")
	_assert(int(stats["point_count"]) > 300, "POI-dense small city fixture renders hundreds of close lights")
	_assert(float(stats["point_diameter_m"]) <= 30.0, "close lights stay small enough to read as lamps/windows rather than blobs")
	_assert(float(stats["glow_diameter_m"]) <= 900.0, "overview clusters cannot become giant regular dots")
	_assert(not bool(stats["glow_visible"]) and bool(stats["points_visible"]), "5 km view uses local points only")
	var points := renderer.get_node_or_null("LocalLightPoints") as MultiMeshInstance3D
	_assert(points != null and points.scale.is_equal_approx(Vector3.ONE), "MultiMesh owner never rescales world positions")
	_assert(not _contains_dynamic_light(renderer), "nationwide layer contains no dynamic OmniLight3D")
	var point_buffer := points.multimesh.buffer
	_assert(point_buffer.size() == points.multimesh.instance_count * MULTIMESH_3D_STRIDE, "local-light MultiMesh exposes the complete production transform buffer")
	var first_origin := _buffer_origin(point_buffer, 0)
	camera.distance_m = 180000.0
	await process_frame
	stats = renderer.get_render_stats()
	_assert(bool(stats["glow_visible"]) and bool(stats["points_visible"]), "180 km transition blends both LODs")
	camera.distance_m = 400000.0
	await process_frame
	stats = renderer.get_render_stats()
	_assert(bool(stats["glow_visible"]) and not bool(stats["points_visible"]), "400 km view uses overview clusters only")
	_assert(_buffer_origin(points.multimesh.buffer, 0).is_equal_approx(first_origin), "LOD never moves physical lights")
	renderer.apply_solar_state({"valid": true, "elevation_deg": 8.0})
	await process_frame
	stats = renderer.get_render_stats()
	_assert(not bool(stats["glow_visible"]) and not bool(stats["points_visible"]), "daylight removes both night layers")
	renderer.queue_free()
	camera.queue_free()
	await process_frame

func _test_large_renderer_multimesh_distribution() -> void:
	var camera := MockCameraRig.new()
	camera.name = "LargeCameraRig"
	root.add_child(camera)
	var renderer = CityLightRendererScript.new()
	renderer.name = "LargeCityLights"
	renderer.camera_rig_path = NodePath("../LargeCameraRig")
	root.add_child(renderer)
	await process_frame
	renderer.begin_urban_data()
	for x in range(260):
		for z in range(260):
			var ox := float(x) * 1000.0
			var oz := float(z) * 1000.0
			renderer.add_urban_triangle(Vector3(ox + 20.0, 0.0, oz + 20.0), Vector3(ox + 400.0, 0.0, oz + 20.0), Vector3(ox + 20.0, 0.0, oz + 400.0))
	renderer.finish_urban_data()
	var points := renderer.get_node_or_null("LocalLightPoints") as MultiMeshInstance3D
	_assert(points != null and points.multimesh != null, "large renderer fixture creates production MultiMesh")
	_assert(points.multimesh.instance_count == 60000, "large renderer fixture reaches the production local-light budget")
	var buffer := points.multimesh.buffer
	_assert(buffer.size() == 60000 * MULTIMESH_3D_STRIDE, "60k MultiMesh keeps a complete transform buffer")
	var first := _buffer_origin(buffer, 0)
	var middle := _buffer_origin(buffer, 30000)
	var last := _buffer_origin(buffer, 59999)
	_assert(first.distance_to(middle) > 10000.0 or first.distance_to(last) > 10000.0, "60k MultiMesh buffer preserves distinct large-scale light positions")
	renderer.queue_free()
	camera.queue_free()
	await process_frame

func _buffer_origin(buffer: PackedFloat32Array, index: int) -> Vector3:
	var offset := index * MULTIMESH_3D_STRIDE
	return Vector3(buffer[offset + 3], buffer[offset + 7], buffer[offset + 11])

func _contains_dynamic_light(node: Node) -> bool:
	for child in node.get_children():
		if child is OmniLight3D or _contains_dynamic_light(child):
			return true
	return false

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("city light test failed: " + message)
	quit(1)
