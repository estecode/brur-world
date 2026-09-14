extends SceneTree

## Headless deterministic regressions for pursuit prediction, refresh and independent unit routing.

const CoordinatorScript = preload("res://scripts/police_pursuit_coordinator.gd")
const PredictorScript = preload("res://scripts/police_pursuit_predictor.gd")
const DriverScript = preload("res://scripts/police_pursuit_driver.gd")
const VehicleScene = preload("res://scenes/vehicle.tscn")

var failures := 0

class FakeRouting:
	extends RefCounted
	var route_calls := 0
	func advance_along_road(position: Vector2, heading_deg: float, distance_m: float) -> Vector2:
		var h := deg_to_rad(heading_deg)
		return position + Vector2(sin(h), -cos(h)) * distance_m
	func route_to_intercept(from: Vector2, target: Vector2) -> Dictionary:
		route_calls += 1
		return {"success": true, "from": from, "target": target, "distance_m": from.distance_to(target)}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_fresh_prediction_is_ahead_on_road()
	_test_stale_observation_is_not_live_tracking()
	_test_route_refresh_before_route_end()
	_test_multiple_units_route_independently()
	await _test_driver_keeps_advancing_on_replaced_route()
	if failures == 0:
		print("POLICE_PURSUIT_TEST=PASS")
		quit(0)
	else:
		push_error("POLICE_PURSUIT_TEST=FAIL count=%d" % failures)
		quit(1)

func _fresh_observation() -> Dictionary:
	return {"position": Vector2(0, 0), "timestamp_s": 10.0, "heading_deg": 90.0, "speed_mps": 20.0, "source_unit_id": "u", "stale": false, "current": true}

func _test_fresh_prediction_is_ahead_on_road() -> void:
	var p = PredictorScript.new().predict(_fresh_observation(), FakeRouting.new())
	_assert(bool(p.get("predicted", false)), "fresh observation predicts ahead")
	_assert((p.get("position", Vector2.ZERO) as Vector2).x > 20.0, "prediction advances along routed heading")

func _test_stale_observation_is_not_live_tracking() -> void:
	var obs := _fresh_observation(); obs["stale"] = true; obs["current"] = false
	var p = PredictorScript.new().predict(obs, FakeRouting.new())
	_assert(not bool(p.get("predicted", true)), "stale observation is not extrapolated")
	_assert((p.get("position", Vector2.INF) as Vector2) == Vector2.ZERO, "stale observation falls back to last known position")

func _test_route_refresh_before_route_end() -> void:
	var routing := FakeRouting.new(); var c = CoordinatorScript.new(); _assert(c.setup(routing), "coordinator accepts routing owner")
	var first := c.update(Vector2(-100, 0), _fresh_observation(), 10.0, -1.0)
	_assert(not first.is_empty(), "initial pursuit route requested")
	var second := c.update(Vector2(-60, 0), _fresh_observation(), 10.1, 20.0)
	_assert(not second.is_empty() and routing.route_calls == 2, "route refreshes before current route ends")

func _test_multiple_units_route_independently() -> void:
	var routing := FakeRouting.new(); var a = CoordinatorScript.new(); var b = CoordinatorScript.new(); a.setup(routing); b.setup(routing)
	var ra := a.update(Vector2(-100, 0), _fresh_observation(), 20.0, -1.0)
	var rb := b.update(Vector2(100, 0), _fresh_observation(), 20.0, -1.0)
	_assert(not ra.is_empty() and not rb.is_empty(), "multiple units independently obtain routes")
	_assert(ra.get("from") != rb.get("from"), "independent routes preserve unit-specific origins")

func _test_driver_keeps_advancing_on_replaced_route() -> void:
	var root := Node.new(); get_root().add_child(root)
	var vehicle := VehicleScene.instantiate() as Node3D; root.add_child(vehicle); vehicle.call("configure", 1)
	var driver := DriverScript.new(); vehicle.add_child(driver); _assert(driver.setup(vehicle), "pursuit driver setup succeeds")
	var route1 := PackedVector3Array([Vector3(0,0,0), Vector3(0,0,-20), Vector3(0,0,-40)])
	_assert(driver.set_route(route1), "driver accepts pursuit route")
	for i in range(20): driver._physics_process(0.1); vehicle._physics_process(0.1)
	var before := float(vehicle.call("speed_mps"))
	var route2 := PackedVector3Array([vehicle.global_position, vehicle.global_position + Vector3(20,0,-20), vehicle.global_position + Vector3(40,0,-40)])
	_assert(driver.set_route(route2), "driver accepts refreshed route before old route ends")
	for i in range(10): driver._physics_process(0.1); vehicle._physics_process(0.1)
	_assert(before > 0.1 and float(vehicle.call("speed_mps")) > 0.1, "refresh does not force repeated stop")
	root.free()

func _assert(condition: bool, message: String) -> void:
	if condition: return
	failures += 1
	push_error(message)
