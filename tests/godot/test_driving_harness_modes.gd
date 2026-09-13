extends SceneTree

## Verifies the driving harness exposes a visible route plus exclusive Manual/GPS ownership and freely switchable AI policy controls.
## Dependencies: production-backed driving harness scene, GpsRouteRenderer, CameraRig, player controller and VehicleRouteFollower public APIs.

const PLAYER_OWNER: int = 0
const GPS_OWNER: int = 1
const FIXTURE_ROUTE_POINT_COUNT: int = 12
const MAX_ROUTE_DEVIATION_M: float = 10.0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://harness/driving/driving_harness.tscn") as PackedScene
	_assert(scene != null, "driving harness scene loads")
	var harness := scene.instantiate()
	get_root().add_child(harness)
	await process_frame

	var control := harness.get_node_or_null("Ui/Panel/Margin/VBox/ControlMode") as OptionButton
	var set_route := harness.get_node_or_null("Ui/Panel/Margin/VBox/SetRoute") as Button
	var clear_route := harness.get_node_or_null("Ui/Panel/Margin/VBox/ClearRoute") as Button
	var selector := harness.get_node_or_null("Ui/Panel/Margin/VBox/DrivingMode") as OptionButton
	var intersection := harness.get_node_or_null("Ui/Panel/Margin/VBox/IntersectionGap") as OptionButton
	var status := harness.get_node_or_null("Ui/Panel/Margin/VBox/Status") as Label
	var camera := harness.get_node_or_null("CameraRig")
	var renderer := harness.get_node_or_null("GpsRouteRenderer")
	var player := harness.get_node_or_null("PlayerVehicle")
	_assert(control != null and control.item_count == 2, "harness exposes Manual Drive and GPS Drive")
	_assert(set_route != null and set_route.text == "Set Route + Start GPS Drive", "harness exposes explicit Set Route control")
	_assert(clear_route != null, "harness exposes explicit Clear Route control")
	_assert(control.get_item_text(0) == "Manual Drive", "first control mode is Manual Drive")
	_assert(control.get_item_text(1) == "GPS Drive", "second control mode is GPS Drive")
	_assert(selector != null and selector.item_count == 3, "harness exposes exactly three AI policy modes")
	_assert(intersection != null and intersection.item_count == 3, "harness exposes deterministic intersection-gap scenarios")
	_assert(status != null, "harness exposes visible route/control status")
	_assert(renderer != null, "driving harness reuses production GPS route renderer")
	_assert(player != null, "driving harness uses production player vehicle")
	_assert(camera != null, "driving harness uses production camera")

	var follower := player.get_node_or_null("VehicleRouteFollower")
	var player_controller := player.get_node_or_null("PlayerVehicleController")
	_assert(follower != null, "driving harness uses production route follower")
	_assert(player_controller != null, "driving harness uses production player controller")

	_assert(int(player.call("control_owner")) == PLAYER_OWNER, "Manual Drive owns the vehicle initially")
	_assert(bool(player_controller.get("enabled")), "player controller is enabled initially")
	_assert(not bool(follower.call("has_route")), "harness starts without an implicit route")
	_assert(int(renderer.call("rendered_point_count")) == 0, "no route is rendered before Set Route")
	_assert(not bool(follower.call("is_follow_enabled")), "GPS follower is disabled before a route is set")
	_assert(bool(camera.call("is_driving_view")), "Manual Drive reserves camera drive mode so WASD cannot pan the map")
	_assert(selector.disabled, "AI style selector is disabled before GPS route start")
	_assert(status.text.contains("Route: NONE"), "visible status reports no route before Set Route")

	var player_instance := player
	var start_position: Vector3 = player.global_position
	# Exercise the exact runtime UI signal wired by the scene, not a harness-private helper.
	set_route.emit_signal("pressed")
	await process_frame
	_assert(bool(follower.call("has_route")), "Set Route installs the production follower route")
	_assert(int(renderer.call("rendered_point_count")) == FIXTURE_ROUTE_POINT_COUNT, "Set Route renders the complete visible route")
	var route_mesh := renderer.get_node_or_null("GpsRoute") as MeshInstance3D
	var target_mesh := renderer.get_node_or_null("GpsTarget") as MeshInstance3D
	_assert(route_mesh != null and route_mesh.mesh != null, "Set Route creates visible route mesh geometry")
	_assert(target_mesh != null and target_mesh.visible, "Set Route shows the visible route destination marker")
	_assert(float(renderer.call("ribbon_width_m")) <= 14.0, "harness route stays at close-drive ribbon width")
	_assert(float(renderer.call("outline_width_m")) <= 25.0, "harness route outline stays bounded")
	_assert(float(renderer.call("target_scale")) < 0.1, "harness destination marker stays compact")
	_assert(float(renderer.call("route_height")) < 1.0, "harness route stays close to the local road surface")
	_assert(bool(follower.call("is_follow_enabled")), "Set Route immediately starts GPS route following")
	_assert(int(player.call("control_owner")) == GPS_OWNER, "Set Route immediately transfers control to GPS")
	_assert(not bool(player_controller.get("enabled")), "player controller releases the vehicle when route starts")
	_assert(control.selected == 1, "Set Route selects GPS Drive in the UI")
	_assert(not selector.disabled, "AI mode selector becomes available once GPS route starts")
	_assert(status.text.contains("Route: SET"), "visible status reports that the route is set")

	for _frame in range(20):
		await physics_frame
	_assert(player.global_position.distance_to(start_position) > 0.01, "vehicle begins moving after Set Route without another follow toggle")

	var position_before_manual: Vector3 = player.global_position
	control.select(0)
	control.item_selected.emit(0)
	await process_frame
	_assert(int(player.call("control_owner")) == PLAYER_OWNER, "Manual Drive can take over an active route")
	_assert(bool(player_controller.get("enabled")), "manual takeover enables player controller")
	_assert(not bool(follower.call("is_follow_enabled")), "manual takeover pauses AI driving")
	_assert(bool(follower.call("has_route")), "manual takeover preserves the active route")
	_assert(int(renderer.call("rendered_point_count")) == FIXTURE_ROUTE_POINT_COUNT, "manual takeover keeps the visible route")
	_assert(harness.get_node_or_null("PlayerVehicle") == player_instance, "manual takeover preserves vehicle instance")
	_assert(player.global_position.distance_to(position_before_manual) < 0.5, "manual takeover does not reset or teleport the vehicle")

	control.select(1)
	control.item_selected.emit(1)
	await process_frame
	_assert(int(player.call("control_owner")) == GPS_OWNER, "GPS Drive can resume the preserved route")
	_assert(bool(follower.call("is_follow_enabled")), "GPS Drive resumes route following")
	_assert(not bool(player_controller.get("enabled")), "GPS resume disables manual player input")
	_assert(bool(follower.call("has_route")), "GPS resume keeps the same route")
	_assert(int(renderer.call("rendered_point_count")) == FIXTURE_ROUTE_POINT_COUNT, "GPS resume keeps the same visible route")
	_assert(harness.get_node_or_null("PlayerVehicle") == player_instance, "GPS resume preserves vehicle instance")

	for index in range(3):
		var position_before_mode: Vector3 = player.global_position
		selector.select(index)
		selector.item_selected.emit(index)
		await process_frame
		_assert(int(follower.call("driving_mode")) == selector.get_item_id(index), "selector updates production AI policy mode")
		_assert(harness.get_node_or_null("PlayerVehicle") == player_instance, "AI mode switching keeps the same production vehicle instance")
		_assert(int(player.call("control_owner")) == GPS_OWNER, "AI mode switching does not change GPS ownership")
		_assert(bool(follower.call("has_route")), "AI mode switching preserves the route")
		_assert(int(renderer.call("rendered_point_count")) == FIXTURE_ROUTE_POINT_COUNT, "AI mode switching preserves the visible route")
		_assert(player.global_position.distance_to(position_before_mode) < 0.5, "AI mode switching does not reset or teleport the vehicle")

	# Reproduce the human failure with several 90-degree turns and assert the actual trajectory,
	# not merely total movement or final distance. The production follower must remain near the polyline.
	var path_route := PackedVector3Array([
		Vector3(-20.0, 0.8, 15.0),
		Vector3(15.0, 0.8, 15.0),
		Vector3(15.0, 0.8, -10.0),
		Vector3(-15.0, 0.8, -10.0),
		Vector3(-15.0, 0.8, 5.0),
	])
	var path_limits := PackedFloat32Array([10.0, 10.0, 10.0, 10.0, 10.0])
	follower.call("set_follow_enabled", false)
	player.call("set_world_position", path_route[0])
	player.call("set_motion_state", 0.0, -PI / 2.0)
	follower.call("set_route", path_route, path_limits)
	follower.call("clear_upcoming_intersection")
	follower.call("set_driving_mode", 1)
	follower.call("set_follow_enabled", true)
	var max_deviation: float = 0.0
	for _frame in range(900):
		await physics_frame
		max_deviation = maxf(max_deviation, _distance_to_polyline(player.global_position, path_route))
	var path_end_distance: float = Vector2(player.global_position.x - path_route[path_route.size() - 1].x, player.global_position.z - path_route[path_route.size() - 1].z).length()
	_assert(max_deviation <= MAX_ROUTE_DEVIATION_M, "GPS trajectory stays inside the route corridor through turns (max deviation %.2f m)" % max_deviation)
	_assert(path_end_distance < 5.0, "GPS trajectory follows the multi-turn path to its final point")
	_assert(float(player.call("speed_mps")) < 1.5, "GPS trajectory brakes at the multi-turn route endpoint")

	clear_route.emit_signal("pressed")
	await process_frame
	_assert(not bool(follower.call("has_route")), "Clear Route removes the route")
	_assert(int(renderer.call("rendered_point_count")) == 0, "Clear Route removes the visible route")
	_assert(route_mesh.mesh == null, "Clear Route removes route mesh geometry")
	_assert(not target_mesh.visible, "Clear Route hides the destination marker")
	_assert(not bool(follower.call("is_follow_enabled")), "Clear Route stops GPS driving")
	_assert(int(player.call("control_owner")) == PLAYER_OWNER, "Clear Route returns control to Manual Drive")
	_assert(bool(player_controller.get("enabled")), "Clear Route restores manual input")
	_assert(status.text.contains("Route: NONE"), "visible status returns to no-route state")
	_assert(harness.get_node_or_null("PlayerVehicle") == player_instance, "Clear Route preserves vehicle instance")

	harness.queue_free()
	print("DRIVING_HARNESS_MODES=PASS")
	quit(0)

func _distance_to_polyline(point: Vector3, points: PackedVector3Array) -> float:
	var best: float = INF
	for index in range(points.size() - 1):
		best = minf(best, _distance_to_segment(point, points[index], points[index + 1]))
	return best

func _distance_to_segment(point: Vector3, a: Vector3, b: Vector3) -> float:
	var p := Vector2(point.x, point.z)
	var av := Vector2(a.x, a.z)
	var bv := Vector2(b.x, b.z)
	var ab := bv - av
	var t := clampf((p - av).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(av + ab * t)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("driving-harness mode test failed: " + message)
	quit(1)
