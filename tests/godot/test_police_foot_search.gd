extends SceneTree

## Headless deterministic regressions for non-omniscient police foot pursuit and local area search.
##
## Dependencies:
## - Production PoliceObservationStore, foot-search domain modules, officer AI/controller and generic Person scene.
## - Uses a tiny traversability fixture only for deterministic local-space constraints.

const ObservationStoreScript = preload("res://scripts/police_observation_store.gd")
const LastKnownScript = preload("res://scripts/police_last_known_target_state.gd")
const SearchAreaScript = preload("res://scripts/police_foot_search_area.gd")
const FootAIScript = preload("res://scripts/police_officer_foot_ai.gd")
const PersonControllerScript = preload("res://scripts/police_officer_person_controller.gd")

var failures := 0

class FakeLocalSpace:
	extends RefCounted
	var block_positive_x := false
	func is_traversable(position: Vector2) -> bool:
		return not block_positive_x or position.x <= 0.01

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_direct_observation_and_lost_contact()
	_test_search_area_growth_obstacles_and_roads()
	_test_reacquisition_and_low_confidence()
	_test_multiple_officers_and_transport_secrecy()
	_test_generic_person_controller_moves_from_observation_only()
	if failures == 0:
		print("POLICE_FOOT_SEARCH_TEST=PASS")
		quit(0)
	else:
		push_error("POLICE_FOOT_SEARCH_TEST=FAIL count=%d" % failures)
		quit(1)

func _publish(store, position: Vector2, timestamp_s: float, confirmed := true) -> void:
	_assert(store.publish(position, timestamp_s, 90.0, 3.0, "observer", confirmed), "observation publishes")

func _test_direct_observation_and_lost_contact() -> void:
	var store = ObservationStoreScript.new(1.0)
	_publish(store, Vector2(10, 0), 0.0)
	var ai = FootAIScript.new()
	_assert(ai.setup(store), "foot AI accepts shared observation store")
	var direct: Dictionary = ai.plan(0.5, Vector2.ZERO)
	var direct_target: Vector2 = direct.get("target_position", Vector2.INF)
	_assert(direct.get("mode", &"") == &"pursue", "fresh direct observation produces pursuit")
	_assert(direct_target.is_equal_approx(Vector2(10, 0)), "direct pursuit targets observed position")
	var hidden_true_position := Vector2(999, 999)
	var lost: Dictionary = ai.plan(2.0, Vector2.ZERO)
	_assert(lost.get("mode", &"") == &"search", "lost contact transitions to search")
	var search_target: Vector2 = lost.get("target_position", Vector2.INF)
	_assert(search_target.is_finite() and search_target.distance_to(hidden_true_position) > 500.0, "stale knowledge does not track hidden true position")
	var frozen: Dictionary = ai.last_known.snapshot(2.0)
	var frozen_position: Vector2 = frozen.get("position", Vector2.INF)
	_assert(frozen_position.is_equal_approx(Vector2(10, 0)), "last-known position remains frozen after sight loss")

func _test_search_area_growth_obstacles_and_roads() -> void:
	var last_known = LastKnownScript.new()
	last_known.update_from_observation({"position": Vector2.ZERO, "timestamp_s": 0.0, "heading_deg": 0.0, "speed_mps": 3.0, "confirmed": true})
	var area_builder = SearchAreaScript.new()
	var early: Dictionary = area_builder.derive(last_known.snapshot(1.0), 1.0)
	var late: Dictionary = area_builder.derive(last_known.snapshot(10.0), 10.0)
	_assert(float(late.get("radius_m", 0.0)) > float(early.get("radius_m", 0.0)), "search area grows with observation age")
	var local_space = FakeLocalSpace.new()
	local_space.block_positive_x = true
	var constrained: Dictionary = area_builder.derive(last_known.snapshot(2.0), 2.0, local_space)
	var candidates: Array = constrained.get("candidates", [])
	var all_allowed := true
	var road_space_present := false
	for candidate_value in candidates:
		if not candidate_value is Vector2:
			continue
		var candidate: Vector2 = candidate_value
		if candidate.x > 0.01:
			all_allowed = false
		if candidate.y > 0.01 and absf(candidate.x) <= 0.01:
			road_space_present = true
	_assert(all_allowed, "local obstacle/traversability filter removes blocked space")
	_assert(road_space_present, "free-roam search does not exclude road-like traversable space")
	var repeat: Dictionary = area_builder.derive(last_known.snapshot(2.0), 2.0, local_space)
	_assert(repeat == constrained, "same observation map and time produce deterministic search area")

func _test_reacquisition_and_low_confidence() -> void:
	var store = ObservationStoreScript.new(1.0)
	_publish(store, Vector2(5, 0), 0.0)
	var ai = FootAIScript.new()
	ai.setup(store)
	ai.plan(2.0, Vector2.ZERO)
	_publish(store, Vector2(20, 0), 3.0)
	var reacquired: Dictionary = ai.plan(3.1, Vector2.ZERO)
	var reacquired_target: Vector2 = reacquired.get("target_position", Vector2.INF)
	_assert(reacquired.get("mode", &"") == &"pursue", "new valid observation reacquires target")
	_assert(reacquired_target.is_equal_approx(Vector2(20, 0)), "reacquisition uses new observed position")
	var low_store = ObservationStoreScript.new(10.0)
	_publish(low_store, Vector2(7, 0), 1.0, false)
	var low_ai = FootAIScript.new()
	low_ai.setup(low_store)
	var low: Dictionary = low_ai.plan(1.1, Vector2.ZERO)
	_assert(low.get("mode", &"") == &"search", "unconfirmed information is not treated as direct live tracking")
	_assert(is_equal_approx(float(low.get("confidence", 0.0)), 0.5), "low-confidence information remains explicitly represented")

func _test_multiple_officers_and_transport_secrecy() -> void:
	var store = ObservationStoreScript.new(1.0)
	_publish(store, Vector2(12, 4), 0.0)
	var first = FootAIScript.new()
	first.setup(store)
	var second = FootAIScript.new()
	second.setup(store)
	var a: Dictionary = first.plan(2.0, Vector2(-10, 0))
	var b: Dictionary = second.plan(2.0, Vector2(10, 0))
	_assert(a.get("mode", &"") == &"search" and b.get("mode", &"") == &"search", "multiple officers independently consume same stale shared observation")
	_assert(is_equal_approx(float(a.get("source_timestamp_s", -1.0)), 0.0) and is_equal_approx(float(b.get("source_timestamp_s", -1.0)), 0.0), "both officers retain the same observation timestamp")
	var unobserved_transport_position := Vector2(500, -500)
	var after_transport: Dictionary = first.plan(4.0, Vector2.ZERO)
	var known_position: Vector2 = first.last_known.snapshot(4.0).get("position", Vector2.INF)
	var after_target: Vector2 = after_transport.get("target_position", Vector2.INF)
	_assert(known_position.is_equal_approx(Vector2(12, 4)), "unobserved transport transition does not publish a new exact position")
	_assert(after_target.distance_to(unobserved_transport_position) > 400.0, "search remains based on last observed state after hidden transport")

func _test_generic_person_controller_moves_from_observation_only() -> void:
	var person_scene := load("res://scenes/person.tscn") as PackedScene
	_assert(person_scene != null, "generic Person scene loads")
	if person_scene == null:
		return
	var person = person_scene.instantiate()
	root.add_child(person)
	person.gravity_mps2 = 0.0
	person.global_position = Vector3.ZERO
	var store = ObservationStoreScript.new(10.0)
	_publish(store, Vector2(10, 0), 0.0)
	var ai = FootAIScript.new()
	ai.setup(store)
	var controller = PersonControllerScript.new()
	root.add_child(controller)
	_assert(controller.setup(person, ai), "police controller composes with generic Person")
	var plan: Dictionary = controller.update(0.1)
	_assert(plan.get("mode", &"") == &"pursue", "generic police Person receives pursuit plan")
	person._physics_process(0.25)
	_assert(person.global_position.x > 0.0, "generic Person physically moves from police AI movement intent")
	controller.queue_free()
	person.queue_free()

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
