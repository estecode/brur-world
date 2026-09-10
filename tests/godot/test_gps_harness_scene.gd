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
	renderer.call("update_height", 20.0)
	var drive_width := float(renderer.call("ribbon_width_m"))
	var drive_target_scale := float(renderer.call("target_scale"))
	_assert(drive_width >= 12.0, "Drive view keeps the GPS ribbon materially readable")
	_assert(drive_target_scale < 0.1, "Drive view keeps the destination marker compact")
	renderer.call("update_height", 900000.0)
	var far_width := float(renderer.call("ribbon_width_m"))
	_assert(far_width > drive_width, "route ribbon widens with camera distance for map readability")
	_assert(route_mesh_instance.mesh != null and route_mesh_instance.mesh.get_surface_count() == 1, "camera-aware width rebuild keeps valid ribbon geometry")

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("gps harness-scene test failed: " + message)
	quit(1)
