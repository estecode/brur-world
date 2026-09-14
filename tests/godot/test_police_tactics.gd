extends SceneTree

## Headless deterministic tests for coordinated police tactic selection, reservation and lifecycle.
##
## Dependencies:
## - Production tactic reservation, spike-strip, roadblock, vehicle-intervention and coordinator modules.
## - Uses a tiny routing API fixture; it does not replace production world/routing in runtime composition.

const ReservationStoreScript = preload("res://scripts/police_tactic_reservation_store.gd")
const SpikeTacticScript = preload("res://scripts/police_spike_strip_tactic.gd")
const RoadblockTacticScript = preload("res://scripts/police_roadblock_tactic.gd")
const InterventionTacticScript = preload("res://scripts/police_vehicle_intervention_tactic.gd")
const CoordinatorScript = preload("res://scripts/police_tactic_coordinator.gd")

var failures := 0

class FakeRouting:
	extends RefCounted
	var valid := true
	func advance_along_road(position: Vector2, heading_deg: float, distance_m: float) -> Vector2:
		if not valid:
			return Vector2(INF, INF)
		var heading := deg_to_rad(heading_deg)
		return position + Vector2(sin(heading), -cos(heading)) * distance_m

func _init() -> void:
	_test_spike_tactic_lifecycle()
	_test_multiple_units_do_not_stack_same_tactic_location()
	_test_new_observation_cancels_and_replans()
	_test_roadblock_lifecycle_and_release()
	_test_roadblock_units_do_not_stack()
	_test_roadblock_replans_and_invalid_falls_back()
	_test_stale_roadblock_falls_back()
	_test_vehicle_intervention_requires_explicit_permission()
	_test_vehicle_intervention_emits_only_driver_intent()
	_test_vehicle_intervention_cancels_and_releases()
	if failures == 0:
		print("POLICE_TACTICS_TEST=PASS")
		quit(0)
	else:
		push_error("POLICE_TACTICS_TEST=FAIL count=%d" % failures)
		quit(1)

func _observation(position: Vector2, timestamp_s: float, current: bool = true, stale: bool = false) -> Dictionary:
	return {"position": position, "heading_deg": 0.0, "speed_mps": 20.0, "timestamp_s": timestamp_s, "current": current, "stale": stale}

func _make_spike_coordinator(unit_id: StringName, store, routing):
	var tactic = SpikeTacticScript.new()
	_assert(tactic.setup(unit_id, routing, store), "spike tactic setup succeeds")
	var coordinator = CoordinatorScript.new()
	coordinator.add_tactic(tactic)
	return coordinator

func _make_roadblock_coordinator(unit_id: StringName, store, routing):
	var tactic = RoadblockTacticScript.new()
	_assert(tactic.setup(unit_id, routing, store), "roadblock tactic setup succeeds")
	var coordinator = CoordinatorScript.new()
	coordinator.add_tactic(tactic)
	return coordinator

func _test_spike_tactic_lifecycle() -> void:
	var store = ReservationStoreScript.new()
	var routing = FakeRouting.new()
	var coordinator = _make_spike_coordinator(&"unit-a", store, routing)
	var plan: Dictionary = coordinator.assign(_observation(Vector2.ZERO, 1.0))
	_assert(plan.get("tactic_id", &"") == &"spike_strip", "unit receives abstract spike-strip assignment")
	_assert(int(plan.get("state", -1)) == SpikeTacticScript.State.REQUESTED, "tactic starts requested")
	var target: Vector2 = plan.get("target_position", Vector2.INF)
	coordinator.update(_observation(Vector2.ZERO, 1.0), 0.1, Vector2.ZERO)
	var preparing: Dictionary = coordinator.update(_observation(Vector2.ZERO, 1.0), 1.1, target)
	_assert(int(preparing.get("state", -1)) == SpikeTacticScript.State.ACTIVE, "requested tactic reaches active after preparation at target")
	var finished: Dictionary = coordinator.update(_observation(Vector2.ZERO, 1.0), 8.1, target)
	_assert(int(finished.get("state", -1)) == SpikeTacticScript.State.FINISHED, "active tactic reaches finished")
	_assert(store.count() == 0, "finished tactic releases reservation")

func _test_multiple_units_do_not_stack_same_tactic_location() -> void:
	var store = ReservationStoreScript.new()
	var routing = FakeRouting.new()
	var first = _make_spike_coordinator(&"unit-a", store, routing)
	var second = _make_spike_coordinator(&"unit-b", store, routing)
	var observation := _observation(Vector2(10, 20), 2.0)
	var a: Dictionary = first.assign(observation)
	var b: Dictionary = second.assign(observation)
	_assert(a.get("tactic_id", &"") == &"spike_strip", "first unit can reserve spike tactic")
	_assert(bool(b.get("fallback", false)) and b.get("tactic_id", &"") == &"intercept", "second unit falls back instead of duplicating same tactic/location")
	_assert(store.count() == 1, "only one conflicting tactic reservation exists")

func _test_new_observation_cancels_and_replans() -> void:
	var store = ReservationStoreScript.new()
	var routing = FakeRouting.new()
	var coordinator = _make_spike_coordinator(&"unit-a", store, routing)
	var first: Dictionary = coordinator.assign(_observation(Vector2.ZERO, 1.0))
	var first_target: Vector2 = first.get("target_position", Vector2.INF)
	var replanned: Dictionary = coordinator.update(_observation(Vector2(100, 0), 2.0), 0.1, Vector2.ZERO)
	var second_target: Vector2 = replanned.get("target_position", Vector2.INF)
	_assert(replanned.get("tactic_id", &"") == &"spike_strip", "fresh changed observation replans tactic")
	_assert(second_target.is_finite() and second_target != first_target, "replan uses a new abstract target")
	_assert(store.count() == 1, "replan replaces rather than leaks reservation")

func _test_roadblock_lifecycle_and_release() -> void:
	var store = ReservationStoreScript.new()
	var routing = FakeRouting.new()
	var coordinator = _make_roadblock_coordinator(&"road-a", store, routing)
	var plan: Dictionary = coordinator.assign(_observation(Vector2.ZERO, 1.0))
	_assert(plan.get("tactic_id", &"") == &"roadblock", "roadblock assignment succeeds")
	var target: Vector2 = plan.get("target_position", Vector2.INF)
	coordinator.update(_observation(Vector2.ZERO, 1.0), 0.1, Vector2.ZERO)
	var active: Dictionary = coordinator.update(_observation(Vector2.ZERO, 1.0), 1.6, target)
	_assert(int(active.get("state", -1)) == RoadblockTacticScript.State.ACTIVE, "roadblock reaches active lifecycle state")
	var finished: Dictionary = coordinator.update(_observation(Vector2.ZERO, 1.0), 10.1, target)
	_assert(int(finished.get("state", -1)) == RoadblockTacticScript.State.FINISHED, "roadblock reaches finished lifecycle state")
	_assert(store.count() == 0, "finished roadblock releases reservation")

func _test_roadblock_units_do_not_stack() -> void:
	var store = ReservationStoreScript.new()
	var routing = FakeRouting.new()
	var first = _make_roadblock_coordinator(&"road-a", store, routing)
	var second = _make_roadblock_coordinator(&"road-b", store, routing)
	var observation := _observation(Vector2(25, 25), 4.0)
	var a: Dictionary = first.assign(observation)
	var b: Dictionary = second.assign(observation)
	_assert(a.get("tactic_id", &"") == &"roadblock", "first unit reserves roadblock")
	_assert(bool(b.get("fallback", false)) and b.get("tactic_id", &"") == &"intercept", "second unit falls back instead of stacking roadblock")
	_assert(store.count() == 1, "only one roadblock reservation exists")

func _test_roadblock_replans_and_invalid_falls_back() -> void:
	var store = ReservationStoreScript.new()
	var routing = FakeRouting.new()
	var coordinator = _make_roadblock_coordinator(&"road-a", store, routing)
	var first: Dictionary = coordinator.assign(_observation(Vector2.ZERO, 1.0))
	var first_target: Vector2 = first.get("target_position", Vector2.INF)
	var replanned: Dictionary = coordinator.update(_observation(Vector2(120, 0), 2.0), 0.1, Vector2.ZERO)
	_assert(replanned.get("tactic_id", &"") == &"roadblock", "changed fresh observation replans roadblock")
	_assert(replanned.get("target_position", Vector2.INF) != first_target, "roadblock replan changes abstract target")
	coordinator.cancel_active()
	_assert(store.count() == 0, "explicit cancellation releases roadblock reservation")
	routing.valid = false
	var fallback: Dictionary = coordinator.assign(_observation(Vector2.ZERO, 3.0))
	_assert(bool(fallback.get("fallback", false)) and fallback.get("tactic_id", &"") == &"intercept", "invalid roadblock assignment falls back to intercept")

func _test_stale_roadblock_falls_back() -> void:
	var store = ReservationStoreScript.new()
	var routing = FakeRouting.new()
	var coordinator = _make_roadblock_coordinator(&"road-a", store, routing)
	var fallback: Dictionary = coordinator.assign(_observation(Vector2(5, 5), 8.0, false, true))
	_assert(bool(fallback.get("fallback", false)) and fallback.get("tactic_id", &"") == &"intercept", "stale observation is not treated as exact live roadblock tracking")
	_assert(store.count() == 0, "stale roadblock request creates no reservation")

func _test_vehicle_intervention_requires_explicit_permission() -> void:
	var store = ReservationStoreScript.new()
	var tactic = InterventionTacticScript.new()
	_assert(tactic.setup(&"int-a", store), "vehicle intervention setup succeeds")
	var coordinator = CoordinatorScript.new()
	coordinator.add_tactic(tactic)
	var blocked: Dictionary = coordinator.assign(_observation(Vector2.ZERO, 1.0))
	_assert(bool(blocked.get("fallback", false)), "vehicle intervention cannot be assigned without explicit permission")
	tactic.set_intervention_allowed(true)
	var selected: Dictionary = coordinator.assign(_observation(Vector2.ZERO, 2.0))
	_assert(selected.get("tactic_id", &"") == &"vehicle_intervention", "vehicle intervention is assigned only when explicitly allowed")

func _test_vehicle_intervention_emits_only_driver_intent() -> void:
	var store = ReservationStoreScript.new()
	var tactic = InterventionTacticScript.new()
	tactic.setup(&"int-a", store)
	tactic.set_intervention_allowed(true)
	var coordinator = CoordinatorScript.new()
	coordinator.add_tactic(tactic)
	coordinator.assign(_observation(Vector2(10, 10), 1.0))
	coordinator.update(_observation(Vector2(10, 10), 1.0), 0.1, Vector2.ZERO)
	coordinator.update(_observation(Vector2(10, 10), 1.0), 0.1, Vector2.ZERO)
	var intent: Dictionary = tactic.driver_intent()
	_assert(intent.get("intent", &"") == &"vehicle_intervention" and bool(intent.get("permitted", false)), "active tactic emits explicit permitted driver intent")
	_assert(not tactic.has_method("set_control_inputs") and not tactic.has_method("apply_force"), "vehicle intervention tactic exposes no low-level Vehicle driving API")

func _test_vehicle_intervention_cancels_and_releases() -> void:
	var store = ReservationStoreScript.new()
	var tactic = InterventionTacticScript.new()
	tactic.setup(&"int-a", store)
	tactic.set_intervention_allowed(true)
	var coordinator = CoordinatorScript.new()
	coordinator.add_tactic(tactic)
	coordinator.assign(_observation(Vector2.ZERO, 1.0))
	_assert(store.count() == 1, "vehicle intervention reserves coordination state")
	var replanned: Dictionary = coordinator.update(_observation(Vector2(100, 0), 2.0), 0.1, Vector2.ZERO)
	_assert(replanned.get("tactic_id", &"") == &"vehicle_intervention", "fresh changed observation can replan vehicle intervention")
	_assert(store.count() == 1, "vehicle intervention replan replaces reservation without leak")
	tactic.set_intervention_allowed(false)
	var fallback: Dictionary = coordinator.update(_observation(Vector2(100, 0), 3.0), 0.1, Vector2.ZERO)
	_assert(bool(fallback.get("fallback", false)) and fallback.get("tactic_id", &"") == &"intercept", "unsupported intervention cancels and falls back conservatively")
	_assert(store.count() == 0, "vehicle intervention cancellation releases coordination state")

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
