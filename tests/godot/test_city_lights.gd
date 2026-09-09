extends SceneTree

## Headless deterministic and structural tests for nighttime city lighting.
## Dependencies: city_light_model.gd and city_light_renderer.gd production code.

const CityLightModelScript = preload("res://scripts/city_light_model.gd")
const CityLightRendererScript = preload("res://scripts/city_light_renderer.gd")

class MockCameraRig:
	extends Node3D
	var distance_m: float = 50000.0

	func get_distance() -> float:
		return distance_m

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var model = CityLightModelScript.new()
	_test_solar_intensity(model)
	_test_distribution(model)
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
	var first: Array[Vector3] = model.light_points()
	_assert(first.size() == 3, "multiple urban triangles in one cell collapse to one light cluster")

	model.reset_distribution()
	for triangle in triangles:
		model.add_urban_triangle(triangle[0], triangle[1], triangle[2])
	var second: Array[Vector3] = model.light_points()
	_assert(first == second, "same urban geometry produces the same light distribution")
	_assert(model.light_points(2).size() == 2, "light distribution respects an explicit point budget")

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

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.add_vertex(Vector3(0.0, 0.0, 0.0))
	surface.add_vertex(Vector3(900.0, 0.0, 0.0))
	surface.add_vertex(Vector3(0.0, 0.0, 900.0))
	var urban_mesh := surface.commit()
	renderer.set_urban_mesh(urban_mesh)
	renderer.finish_urban_data()
	renderer.apply_solar_state({"valid": true, "elevation_deg": -8.0})
	await process_frame

	var stats: Dictionary = renderer.get_render_stats()
	_assert(is_equal_approx(float(stats["night_intensity"]), 1.0), "renderer consumes solar elevation through the city-light model")
	_assert(int(stats["point_count"]) == 2, "renderer builds one batched point per selected urban cell")
	_assert(int(stats["point_count"]) <= int(stats["max_point_count"]), "renderer respects its explicit nationwide point budget")
	_assert(bool(stats["glow_visible"]), "urban glow is visible at night")
	_assert(bool(stats["points_visible"]), "local light points are visible at closer camera distance")

	var glow := renderer.get_node_or_null("UrbanGlow") as MeshInstance3D
	var points := renderer.get_node_or_null("LocalLightPoints") as MultiMeshInstance3D
	_assert(glow != null and glow.mesh == urban_mesh, "far glow reuses the authoritative urban mesh instead of rebuilding city truth")
	_assert(points != null and points.multimesh != null and points.multimesh.instance_count == 2, "local lights use one MultiMesh")
	_assert(not _contains_dynamic_light(renderer), "city layer creates no nationwide dynamic OmniLight3D instances")

	var first_transform := points.multimesh.get_instance_transform(0)
	camera.distance_m = 400000.0
	await process_frame
	stats = renderer.get_render_stats()
	_assert(bool(stats["glow_visible"]), "far overview keeps aggregate urban glow")
	_assert(not bool(stats["points_visible"]), "far overview hides local point detail")
	_assert(points.multimesh.get_instance_transform(0).is_equal_approx(first_transform), "camera LOD does not move or rescale physical light positions")

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
