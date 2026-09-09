extends SceneTree

## Headless deterministic, structural, and production-composition tests for nighttime city lighting.
## Dependencies: city_light_model.gd, city_light_renderer.gd, day_night_environment_adapter.gd, main.gd, and scenes/main.tscn.

const CityLightModelScript = preload("res://scripts/city_light_model.gd")
const CityLightRendererScript = preload("res://scripts/city_light_renderer.gd")
const DayNightEnvironmentAdapterScript = preload("res://scripts/day_night_environment_adapter.gd")

class MockCameraRig:
	extends Node3D
	var distance_m: float = 50000.0

	func get_distance() -> float:
		return distance_m

class MockSunController:
	extends Node
	signal solar_state_changed(solar_state: Dictionary)
	var state: Dictionary = {"valid": true, "elevation_deg": -8.0}

	func get_last_solar_state() -> Dictionary:
		return state.duplicate(true)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var model = CityLightModelScript.new()
	_test_solar_intensity(model)
	_test_distribution(model)
	_test_production_composition()
	await _test_environment_contrast()
	await _test_renderer_structure()
	print("godot city light tests: OK")
	quit(0)

func _test_solar_intensity(model) -> void:
	_assert(is_zero_approx(model.night_intensity(5.0)), "daylight disables city lighting")
	var dusk := float(model.night_intensity(-2.0))
	_assert(dusk > 0.0 and dusk < 1.0, "dusk fades city lighting instead of switching abruptly")
	_assert(is_equal_approx(float(model.night_intensity(-8.0)), 1.0), "deep night reaches full configured intensity")
	_assert(float(model.night_intensity(-4.0)) > dusk, "night intensity increases monotonically as the sun descends")

func _test_distribution(model) -> void:
	var triangles := [
		[Vector3(100.0, 0.0, 100.0), Vector3(500.0, 0.0, 100.0), Vector3(100.0, 0.0, 500.0)],
		[Vector3(200.0, 0.0, 200.0), Vector3(600.0, 0.0, 200.0), Vector3(200.0, 0.0, 600.0)],
		[Vector3(2200.0, 0.0, 100.0), Vector3(2600.0, 0.0, 100.0), Vector3(2200.0, 0.0, 500.0)],
		[Vector3(-2200.0, 0.0, -100.0), Vector3(-1800.0, 0.0, -100.0), Vector3(-2200.0, 0.0, -500.0)],
	]
	for triangle in triangles:
		model.add_urban_triangle(triangle[0], triangle[1], triangle[2])
	var overview: Array[Vector3] = model.overview_points()
	var local: Array[Vector3] = model.local_light_points()
	_assert(overview.size() == 3, "multiple urban triangles in one cell collapse to one overview cluster")
	_assert(local.size() == 9, "local presentation expands each urban cell into several deterministic light points")
	_assert(local[0] != overview[0], "local lights are distributed within the urban cell rather than sitting on the glow center")

	model.reset_distribution()
	for triangle in triangles:
		model.add_urban_triangle(triangle[0], triangle[1], triangle[2])
	_assert(overview == model.overview_points(), "same urban geometry produces the same overview distribution")
	_assert(local == model.local_light_points(), "same urban geometry produces the same local-light distribution")
	_assert(model.local_light_points(4).size() == 4, "local distribution respects an explicit point budget")

func _test_production_composition() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	_assert(scene != null, "production main scene loads")
	var instance := scene.instantiate()
	_assert(instance.get_node_or_null("DayNightEnvironment") != null, "production main scene includes the day/night environment adapter")
	var adapter := instance.get_node_or_null("DayNightEnvironment")
	_assert(adapter != null and adapter.sun_controller_path == NodePath("../SunRuntimeController"), "day/night adapter explicitly consumes production solar state")
	_assert(adapter != null and adapter.world_environment_path == NodePath("../WorldEnvironment"), "day/night adapter explicitly owns only the production environment presentation")
	instance.free()

	var main_file := FileAccess.open("res://scripts/main.gd", FileAccess.READ)
	_assert(main_file != null, "production main composition source is readable")
	if main_file != null:
		var source := main_file.get_as_text()
		_assert(source.contains("_setup_city_lights()"), "production main explicitly composes city lights")
		_assert(source.contains("city_lights.begin_urban_data()"), "production main feeds authoritative BRM2 urban data into city lights")

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
	var stats: Dictionary = adapter.get_environment_stats()
	_assert(float(stats["night_factor"]) > 0.99, "deep night drives the environment to full night presentation")
	_assert(night_energy < day_energy * 0.30, "night ambient energy remains substantially darker than daylight")
	_assert(night_background.get_luminance() < day_background.get_luminance() * 0.30, "night background remains substantially darker than daylight")
	_assert(night_background.b > night_background.r, "night presentation keeps a readable dark-blue base instead of collapsing to black")

	host.queue_free()
	await process_frame

func _test_renderer_structure() -> void:
	var camera := MockCameraRig.new()
	camera.name = "CameraRig"
	root.add_child(camera)

	var renderer = CityLightRendererScript.new()
	renderer.name = "CityLights"
	renderer.camera_rig_path = NodePath("../CameraRig")
	root.add_child(renderer)
	await process_frame

	renderer.begin_urban_data()
	renderer.add_urban_triangle(Vector3(0.0, 0.0, 0.0), Vector3(900.0, 0.0, 0.0), Vector3(0.0, 0.0, 900.0))
	renderer.add_urban_triangle(Vector3(3000.0, 0.0, 0.0), Vector3(3900.0, 0.0, 0.0), Vector3(3000.0, 0.0, 900.0))
	renderer.finish_urban_data()
	renderer.apply_solar_state({"valid": true, "elevation_deg": -8.0})
	await process_frame

	var stats: Dictionary = renderer.get_render_stats()
	_assert(is_equal_approx(float(stats["night_intensity"]), 1.0), "renderer consumes solar elevation through the city-light model")
	_assert(int(stats["glow_count"]) == 2, "renderer builds one overview glow cluster per selected urban cell")
	_assert(int(stats["point_count"]) == 6, "renderer builds several local lights per selected urban cell")
	_assert(int(stats["glow_count"]) <= int(stats["max_glow_count"]), "overview glow respects its explicit batch budget")
	_assert(int(stats["point_count"]) <= int(stats["max_point_count"]), "local lights respect their explicit nationwide point budget")
	_assert(not bool(stats["glow_visible"]), "close view removes large glow clusters so urban polygons do not read as filled orange areas")
	_assert(bool(stats["points_visible"]), "close view shows local light points")

	var glow := renderer.get_node_or_null("UrbanGlowClusters") as MultiMeshInstance3D
	var points := renderer.get_node_or_null("LocalLightPoints") as MultiMeshInstance3D
	_assert(glow != null and glow.multimesh != null and glow.multimesh.instance_count == 2, "far glow uses one batched MultiMesh instead of the filled urban polygon mesh")
	_assert(points != null and points.multimesh != null and points.multimesh.instance_count == 6, "local lights use one batched MultiMesh")
	_assert(glow.scale.is_equal_approx(Vector3.ONE) and points.scale.is_equal_approx(Vector3.ONE), "MultiMesh owners stay unscaled so world positions remain stable")
	_assert(not _contains_dynamic_light(renderer), "city layer creates no nationwide dynamic OmniLight3D instances")

	var first_transform := points.multimesh.get_instance_transform(0)
	_assert(first_transform.origin.length() < 10000.0, "local light remains near its authoritative urban source")
	camera.distance_m = 180000.0
	await process_frame
	stats = renderer.get_render_stats()
	_assert(bool(stats["glow_visible"]) and bool(stats["points_visible"]), "mid-distance band blends overview clusters with local lights")
	camera.distance_m = 400000.0
	await process_frame
	stats = renderer.get_render_stats()
	_assert(bool(stats["glow_visible"]), "far overview keeps aggregate urban glow clusters")
	_assert(not bool(stats["points_visible"]), "far overview hides local point detail")
	_assert(points.multimesh.get_instance_transform(0).origin.is_equal_approx(first_transform.origin), "camera LOD does not move physical light positions")

	renderer.apply_solar_state({"valid": true, "elevation_deg": 8.0})
	await process_frame
	stats = renderer.get_render_stats()
	_assert(not bool(stats["glow_visible"]) and not bool(stats["points_visible"]), "daylight removes nighttime presentation")

	renderer.queue_free()
	camera.queue_free()
	await process_frame

func _contains_dynamic_light(node: Node) -> bool:
	for child in node.get_children():
		if child is OmniLight3D:
			return true
		if _contains_dynamic_light(child):
			return true
	return false

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("city light test failed: " + message)
	quit(1)
