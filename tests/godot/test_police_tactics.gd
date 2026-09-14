extends SceneTree

## Headless deterministic tests for coordinated police tactic selection, reservation and lifecycle.
##
## Dependencies:
## - Production tactic reservation, spike-strip tactic, selector and coordinator modules.
## - Uses a tiny routing API fixture; it does not replace production world/routing in runtime composition.

const ReservationStoreScript = preload("res://scripts/police_tactic_reservation_store.gd")
const SpikeTacticScript = preload("res://scripts/police_spike_strip_tactic.gd")
const CoordinatorScript = preload("res://scripts/police_tactic_coordinator.gd")

var failures := 0

class FakeRouting:
	extends RefCounted
	func advance_along_road(position: Vector2, heading_deg: float, distance_m: float) -> Vector2:
		var heading := deg_to_rad(heading_deg)
		return position + Vector2(sin(heading), -cos(heading)) * distance_m

func _init() -> void:
	_test_spike_tactic_lifecycle()
	_test_multiple_units_do_not_stack_same_tactic_location()
	_test_new_observation_cancels_and_replans()
	if failures == 0:
		print("POLICE_TACTICS_TEST=PASS")
		quit(0)
	else:
		push_error("POLICE_TACTICS_TEST=FAIL count=%d" % failures)
		quit(1)

func _observation(position: Vector2, timestamp_s: float) -> Dictionary:
	return {"position": position, "heading_deg": 0.0, "speed_mps": 20.0, "timestamp_s": timestamp_s, "current": true, "stale": false}

func _make_coordinator(unit_id: StringName, store, routing):
	var tactic = SpikeTacticScript.new()
	_assert(tactic.setup(unit_id, routing, store), "spike tactic setup succeeds")
	var coordinator = CoordinatorScript.new()
	coordinator.add_tactic(tactic)
	return coordinator

func _test_spike_tactic_lifecycle() -> void:
	var store = ReservationStoreScript.new()
	var routing = FakeRouting.new()
	var coordinator = _make_coordinator(&"unit-a", store, routing)
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
	var first = _make_coordinator(&"unit-a", store, routing)
	var second = _make_coordinator(&"unit-b", store, routing)
	var observation := _observation(Vector2(10, 20), 2.0)
	var a: Dictionary = first.assign(observation)
	var b: Dictionary = second.assign(observation)
	_assert(a.get("tactic_id", &"") == &"spike_strip", "first unit can reserve spike tactic")
	_assert(bool(b.get("fallback", false)) and b.get("tactic_id", &"") == &"intercept", "second unit falls back instead of duplicating same tactic/location")
	_assert(store.count() == 1, "only one conflicting tactic reservation exists")

func _test_new_observation_cancels_and_replans() -> void:
	var store = ReservationStoreScript.new()
	var routing = FakeRouting.new()
	var coordinator = _make_coordinator(&"unit-a", store, routing)
	var first: Dictionary = coordinator.assign(_observation(Vector2.ZERO, 1.0))
	var first_target: Vector2 = first.get("target_position", Vector2.INF)
	var replanned: Dictionary = coordinator.update(_observation(Vector2(100, 0), 2.0), 0.1, Vector2.ZERO)
	var second_target: Vector2 = replanned.get("target_position", Vector2.INF)
	_assert(replanned.get("tactic_id", &"") == &"spike_strip", "fresh changed observation replans tactic")
	_assert(second_target.is_finite() and second_target != first_target, "replan uses a new abstract target")
	_assert(store.count() == 1, "replan replaces rather than leaks reservation")

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
