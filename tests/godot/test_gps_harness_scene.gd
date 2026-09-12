extends SceneTree

## Loads and drives the production GPS harness scene headlessly.
## Dependencies: harness/gps/gps_harness.tscn and the production GPS modules composed by it.

const HARNESS_SCENE := preload("res://harness/gps/gps_harness.tscn")

var harness: Node

func _init() -> void:
	harness = HARNESS_SCENE.instantiate()
	root.add_child(harness)
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var renderer: Node = harness.get_node("GpsRouteRenderer")
	var model = harness.get("model")

	_assert(int(renderer.call("rendered_point_count")) == 3, "scene starts with direct fixture rendered")
	_assert(bool(model.has_destination()), "direct fixture owns a destination")
	_assert(int(model.waypoint_count()) == 0, "direct fixture has no waypoint")
	_test_route_ribbon_contract(renderer)

	harness.call("show_waypoint_fixture")
	_assert(int(renderer.call("rendered_point_count")) == 3, "waypoint fixture renders all route points")
	_assert(int(model.waypoint_count()) == 1, "waypoint fixture owns one waypoint")

	harness.call("show_failure_fixture")
	_assert(int(renderer.call("rendered_point_count")) == 0, "failure fixture clears route geometry")

	for preference: String in ["fastest", "shortest", "avoid_small_roads", "avoid_major_roads"]:
		harness.call("_set_preference", preference)
		_assert(str(model.preference()) == preference, "harness applies preference %s" % preference)

	print("godot gps harness-scene tests: OK")
	quit(0)

func _test_route_ribbon_contract(renderer: Node) -> void:
	var route_mesh_instance := renderer.get_node("GpsRoute") as MeshInstance3D
	_assert(route_mesh_instance != null and route_mesh_instance.mesh != null, "GPS route owns generated presentation mesh")
	_assert(route_mesh_instance.mesh.get_surface_count() == 1, "GPS route ribbon has one generated surface")
	_assert(route_mesh_instance.mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES, "GPS route uses a triangle ribbon instead of a line strip")
	var route_material := route_mesh_instance.material_override as StandardMaterial3D
	_assert(route_material != null, "GPS route owns an explicit presentation material")
	_assert(route_material.albedo_color.get_luminance() < 0.05, "GPS route uses a near-black high-contrast color")
	_assert(route_material.no_depth_test, "GPS route stays visually above map geometry")

	renderer.call("update_height", 20.0)
	var drive_width := float(renderer.call("ribbon_width_m"))
	var drive_target_scale := float(renderer.call("target_scale"))
	_assert(is_equal_approx(drive_width, 12.0), "Drive view keeps a proportionate 12 m GPS ribbon")
	_assert(drive_target_scale < 0.1, "Drive view keeps the destination marker compact")

	renderer.call("update_height", 5700.0)
	var map_width := float(renderer.call("ribbon_width_m"))
	_assert(map_width >= 40.0, "5-6 km map view makes the GPS route materially wider than rendered roads")
	_assert(map_width > drive_width, "route ribbon grows between drive and map view")

	renderer.call("update_height", 900000.0)
	var far_width := float(renderer.call("ribbon_width_m"))
	_assert(far_width > map_width, "route ribbon continues widening for far-map readability")
	_assert(far_width <= 1200.0, "far-map route width remains bounded")
	_assert(route_mesh_instance.mesh != null and route_mesh_instance.mesh.get_surface_count() == 1, "camera-aware width rebuild keeps valid ribbon geometry")

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("gps harness-scene test failed: " + message)
	quit(1)
