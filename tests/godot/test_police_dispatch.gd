extends SceneTree

## Headless deterministic contract tests for finite police resources and dispatch.
## Dependencies: scripts/police_unit.gd, police_dispatch.gd, and police_route_estimate.gd only.

const PoliceUnitScript = preload("res://scripts/police_unit.gd")
const PoliceDispatchScript = preload("res://scripts/police_dispatch.gd")
const PoliceRouteEstimateScript = preload("res://scripts/police_route_estimate.gd")


func _init() -> void:
	_test_nearest_available_unit_and_finite_capacity()
	_test_priority_queue_and_release_reassignment()
	_test_role_compatibility_and_route_failures()
	_test_deterministic_tie_breaking()
	_test_travel_delay_and_arrival()
	_test_gps_route_response_adapter()
	_test_save_load_exact_state()
	print("godot police-dispatch tests: OK")
	quit(0)


func _test_nearest_available_unit_and_finite_capacity() -> void:
	var dispatch = PoliceDispatchScript.new()
	_assert(dispatch.add_unit(PoliceUnitScript.new("patrol-a", &"patrol", Vector2(0.0, 0.0))), "adds first patrol")
	_assert(dispatch.add_unit(PoliceUnitScript.new("patrol-b", &"patrol", Vector2(1000.0, 0.0))), "adds second patrol")
	_assert(dispatch.submit_incident("incident-1", Vector2(150.0, 0.0), 2), "submits first incident")
	var first := dispatch.dispatch_pending(Callable(self, "_road_estimate"))
	_assert(first.size() == 1, "first incident is dispatched")
	_assert(str(first[0]["unit_id"]) == "patrol-a", "lowest routed travel time wins")
	_assert(not dispatch.get_unit("patrol-a").is_available(), "assigned unit becomes busy")

	_assert(dispatch.submit_incident("incident-2", Vector2(180.0, 0.0), 2), "submits simultaneous incident")
	var second := dispatch.dispatch_pending(Callable(self, "_road_estimate"))
	_assert(second.size() == 1, "second incident uses remaining finite capacity")
	_assert(str(second[0]["unit_id"]) == "patrol-b", "busy nearest unit cannot receive a second assignment")

	_assert(dispatch.submit_incident("incident-3", Vector2(200.0, 0.0), 2), "submits over-capacity incident")
	_assert(dispatch.dispatch_pending(Callable(self, "_road_estimate")).is_empty(), "no unlimited police resource is spawned")
	_assert(dispatch.pending_incidents().size() == 1, "over-capacity incident remains pending")
	_assert(dispatch.available_unit_count(&"patrol") == 0, "both patrol resources are consumed")


func _test_priority_queue_and_release_reassignment() -> void:
	var dispatch = PoliceDispatchScript.new()
	dispatch.add_unit(PoliceUnitScript.new("solo", &"patrol", Vector2.ZERO))
	dispatch.submit_incident("occupy", Vector2(10.0, 0.0), 1)
	dispatch.dispatch_pending(Callable(self, "_road_estimate"))
	dispatch.submit_incident("low", Vector2(20.0, 0.0), 1)
	dispatch.submit_incident("high", Vector2(30.0, 0.0), 9)
	_assert(dispatch.dispatch_pending(Callable(self, "_road_estimate")).is_empty(), "queued incidents wait while unit is busy")
	_assert(dispatch.release_incident("occupy"), "release returns resource to pool")
	var next := dispatch.dispatch_pending(Callable(self, "_road_estimate"))
	_assert(next.size() == 1 and str(next[0]["incident_id"]) == "high", "higher-priority waiting incident consumes released resource first")
	_assert(dispatch.pending_incidents().size() == 1 and str(dispatch.pending_incidents()[0]["incident_id"]) == "low", "lower priority remains queued")
	_assert(dispatch.release_incident("high"), "high-priority assignment can be released")
	var final := dispatch.dispatch_pending(Callable(self, "_road_estimate"))
	_assert(final.size() == 1 and str(final[0]["incident_id"]) == "low", "released unit can be reassigned")


func _test_role_compatibility_and_route_failures() -> void:
	var dispatch = PoliceDispatchScript.new()
	dispatch.add_unit(PoliceUnitScript.new("patrol", &"patrol", Vector2.ZERO))
	dispatch.add_unit(PoliceUnitScript.new("traffic", &"traffic", Vector2(500.0, 0.0)))
	dispatch.submit_incident("traffic-job", Vector2(5.0, 0.0), 1, &"traffic")
	var result := dispatch.dispatch_pending(Callable(self, "_road_estimate"))
	_assert(result.size() == 1 and str(result[0]["unit_id"]) == "traffic", "dispatch honors explicit compatible role")

	var unreachable = PoliceDispatchScript.new()
	unreachable.add_unit(PoliceUnitScript.new("patrol", &"patrol", Vector2.ZERO))
	unreachable.submit_incident("blocked", Vector2(100.0, 0.0), 1)
	_assert(unreachable.dispatch_pending(Callable(self, "_failed_estimate")).is_empty(), "route failure cannot create a response assignment")
	_assert(unreachable.pending_incidents().size() == 1, "unroutable incident remains pending")


func _test_deterministic_tie_breaking() -> void:
	var dispatch = PoliceDispatchScript.new()
	dispatch.add_unit(PoliceUnitScript.new("bravo", &"patrol", Vector2(-100.0, 0.0)))
	dispatch.add_unit(PoliceUnitScript.new("alpha", &"patrol", Vector2(100.0, 0.0)))
	dispatch.submit_incident("tie", Vector2.ZERO, 1)
	var result := dispatch.dispatch_pending(Callable(self, "_road_estimate"))
	_assert(result.size() == 1 and str(result[0]["unit_id"]) == "alpha", "equal route cost ties break by stable unit id")


func _test_travel_delay_and_arrival() -> void:
	var dispatch = PoliceDispatchScript.new()
	dispatch.add_unit(PoliceUnitScript.new("patrol", &"patrol", Vector2.ZERO))
	dispatch.submit_incident("travel", Vector2(300.0, 0.0), 1)
	var result := dispatch.dispatch_pending(Callable(self, "_road_estimate"))
	_assert(result.size() == 1, "travel incident is assigned")
	var route_time := float(result[0]["travel_time_s"])
	_assert(route_time > 0.0, "routing cost produces non-zero response delay")
	_assert(dispatch.advance(route_time - 0.01).is_empty(), "unit does not arrive before routed travel time")
	var arrivals := dispatch.advance(0.01)
	_assert(arrivals.size() == 1 and str(arrivals[0]["incident_id"]) == "travel", "unit arrives when routed travel time elapses")
	_assert(not dispatch.get_unit("patrol").is_available(), "arrival alone does not magically free resource")
	_assert(dispatch.release_incident("travel"), "scene completion explicitly releases resource")
	_assert(dispatch.get_unit("patrol").is_available(), "released unit becomes available again")
	_assert(dispatch.get_unit("patrol").position.is_equal_approx(Vector2(300.0, 0.0)), "released unit persists at incident location")


func _test_gps_route_response_adapter() -> void:
	var estimate: Dictionary = PoliceRouteEstimateScript.from_gps_response({
		"success": true,
		"distance_m": 1234.5,
		"travel_time_s": 98.25,
		"points": [[0.0, 0.0], [1.0, 1.0]],
	})
	_assert(bool(estimate.get("success", false)), "successful native GPS response becomes a dispatch estimate")
	_assert(is_equal_approx(float(estimate["distance_m"]), 1234.5), "GPS route distance is preserved")
	_assert(is_equal_approx(float(estimate["travel_time_s"]), 98.25), "GPS authoritative travel time is preserved")
	_assert(not bool(PoliceRouteEstimateScript.from_gps_response({"success": false}).get("success", true)), "failed GPS route is rejected")
	_assert(not bool(PoliceRouteEstimateScript.from_gps_response({"success": true, "distance_m": 1.0}).get("success", true)), "missing travel time fails closed")


func _test_save_load_exact_state() -> void:
	var dispatch = PoliceDispatchScript.new()
	dispatch.add_unit(PoliceUnitScript.new("patrol-a", &"patrol", Vector2(10.0, 20.0)))
	dispatch.add_unit(PoliceUnitScript.new("patrol-b", &"patrol", Vector2(500.0, 20.0)))
	dispatch.submit_incident("active", Vector2(100.0, 20.0), 4)
	dispatch.dispatch_pending(Callable(self, "_road_estimate"))
	dispatch.advance(1.25)
	dispatch.submit_incident("pending", Vector2(900.0, 20.0), 7, &"traffic")
	var saved := dispatch.save_state()
	var restored = PoliceDispatchScript.new()
	restored.load_state(saved)
	_assert(restored.save_state() == saved, "save/load restores units, busy assignment, queue, travel delay, and ordering")
	_assert(not restored.get_unit("patrol-a").is_available(), "busy resource remains busy after restore")
	_assert(restored.pending_incidents().size() == 1, "pending incident survives restore")


func _road_estimate(start: Vector2, target: Vector2, _role: StringName) -> Dictionary:
	var distance_m := start.distance_to(target)
	return {
		"success": true,
		"distance_m": distance_m,
		"travel_time_s": distance_m / 15.0,
	}


func _failed_estimate(_start: Vector2, _target: Vector2, _role: StringName) -> Dictionary:
	return {"success": false}


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("police-dispatch test failed: " + message)
	quit(1)
