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
	_assert((renderer.get_node("GpsRoute") as MeshInstance3D).mesh == null, "failure fixture clears route core mesh")
	_assert((renderer.get_node("GpsRouteOutline") as MeshInstance3D).mesh == null, "failure fixture clears route outline mesh")

	for preference: String in ["fastest", "shortest", "avoid_small_roads", "avoid_major_roads"]:
		harness.call("_set_preference", preference)
		_assert(str(model.preference()) == preference, "harness applies preference %s" % preference)

	print("godot gps harness-scene tests: OK")
	quit(0)

func _test_route_ribbon_contract(renderer: Node) -> void:
	var route_mesh_instance := renderer.get_node("GpsRoute") as MeshInstance3D
	var outline_mesh_instance := renderer.get_node("GpsRouteOutline") as MeshInstance3D
	_assert(route_mesh_instance != null and route_mesh_instance.mesh != null, "GPS route owns generated presentation mesh")
	_assert(outline_mesh_instance != null and outline_mesh_instance.mesh != null, "GPS route owns generated contrast outline mesh")
	_assert(route_mesh_instance.mesh.get_surface_count() == 1, "GPS route ribbon has one generated surface")
	_assert(outline_mesh_instance.mesh.get_surface_count() == 1, "GPS route outline has one generated surface")
	_assert(route_mesh_instance.mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES, "GPS route uses a triangle ribbon instead of a line strip")
	_assert(outline_mesh_instance.mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES, "GPS route outline uses the same triangle-ribbon geometry")

	var route_material := route_mesh_instance.material_override as StandardMaterial3D
	var outline_material := outline_mesh_instance.material_override as StandardMaterial3D
	_assert(route_material != null, "GPS route owns an explicit presentation material")
	_assert(outline_material != null, "GPS route outline owns an explicit presentation material")
	_assert(route_material.albedo_color.get_luminance() < 0.05, "GPS route keeps a near-black core")
	_assert(outline_material.albedo_color.get_luminance() > 0.8, "GPS route owns a bright contrast outline")
	_assert(route_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "GPS route core renders in the ordered transparent pass")
	_assert(outline_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "GPS route outline renders in the ordered transparent pass")
	_assert(route_material.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED, "GPS route core cannot be hidden by depth-write competition")
	_assert(outline_material.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED, "GPS route outline cannot be hidden by depth-write competition")
	_assert(route_material.no_depth_test and outline_material.no_depth_test, "GPS route overlay ignores map depth")
	_assert(route_material.cull_mode == BaseMaterial3D.CULL_DISABLED and outline_material.cull_mode == BaseMaterial3D.CULL_DISABLED, "GPS route stays visible from every camera tilt")
	_assert(outline_material.render_priority > 0, "GPS route outline renders after background map classes")
	_assert(route_material.render_priority > outline_material.render_priority, "GPS route core renders after its outline")

	renderer.call("update_height", 20.0)
	var drive_width := float(renderer.call("ribbon_width_m"))
	var drive_outline_width := float(renderer.call("outline_width_m"))
	var drive_target_scale := float(renderer.call("target_scale"))
	_assert(is_equal_approx(drive_width, 14.0), "Drive view keeps a slightly stronger but proportionate 14 m GPS ribbon")
	_assert(drive_outline_width > drive_width, "Drive view keeps a visible contrast outline around the route")
	_assert(drive_target_scale < 0.1, "Drive view keeps the destination marker compact")

	renderer.call("update_height", 5700.0)
	var map_width := float(renderer.call("ribbon_width_m"))
	var map_outline_width := float(renderer.call("outline_width_m"))
	_assert(map_width >= 50.0, "5-6 km map view makes the GPS route clearly wider than rendered roads")
	_assert(map_width > drive_width, "route ribbon grows between drive and map view")
	_assert(map_outline_width > map_width, "5-6 km map view preserves the contrast outline")

	renderer.call("update_height", 900000.0)
	var far_width := float(renderer.call("ribbon_width_m"))
	_assert(far_width > map_width, "route ribbon continues widening for far-map readability")
	_assert(far_width <= 4200.0, "far-map route width remains bounded")

	# The production camera tops out around 1.4 Mm altitude, which yields a
	# roughly 1.5 Mm camera distance. Keep the route visible there without
	# turning it into a country-scale band.
	renderer.call("update_height", 1500000.0)
	var max_zoom_width := float(renderer.call("ribbon_width_m"))
	var max_zoom_outline_width := float(renderer.call("outline_width_m"))
	_assert(max_zoom_width >= 3500.0, "maximum zoom-out keeps the route visibly scaled")
	_assert(max_zoom_width <= 4200.0, "maximum zoom-out route core stays capped")
	_assert(max_zoom_width / 1500000.0 < 0.003, "maximum zoom-out route remains a small fraction of camera distance")
	_assert(max_zoom_outline_width > max_zoom_width, "maximum zoom-out preserves a visible outline")
	_assert(max_zoom_outline_width / 1500000.0 < 0.004, "maximum zoom-out outline remains proportionate")
	_assert(route_mesh_instance.mesh != null and route_mesh_instance.mesh.get_surface_count() == 1, "camera-aware width rebuild keeps valid core ribbon geometry")
	_assert(outline_mesh_instance.mesh != null and outline_mesh_instance.mesh.get_surface_count() == 1, "camera-aware width rebuild keeps valid outline geometry")

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("gps harness-scene test failed: " + message)
	quit(1)
