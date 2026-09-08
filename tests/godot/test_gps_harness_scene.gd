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

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("gps harness-scene test failed: " + message)
	quit(1)
