extends SceneTree

## Headless deterministic tests for pedestrian route preference, danger response, and lightweight/full Person promotion.
##
## Dependencies:
## - Production PedestrianRoutePolicy, PedestrianAI, PedestrianAgent and PedestrianPopulation.
## - Production generic Person scene and PersonMovementModel from the #18 foundation.

const RoutePolicyScript = preload("res://scripts/pedestrian_route_policy.gd")
const PedestrianAIScript = preload("res://scripts/pedestrian_ai.gd")
const PedestrianAgentScript = preload("res://scripts/pedestrian_agent.gd")
const PedestrianPopulationScript = preload("res://scripts/pedestrian_population.gd")
const PersonMovementModelScript = preload("res://scripts/person_movement_model.gd")

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_route_preferences_and_fallback()
	_test_deterministic_ai_and_danger_response()
	_test_lightweight_motion()
	await _test_population_promotion_and_demotion()
	if _failures.is_empty():
		print("PEDESTRIAN_POPULATION_TEST=PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("PEDESTRIAN_POPULATION_TEST=FAIL count=%d" % _failures.size())
		quit(1)

func _test_route_preferences_and_fallback() -> void:
	var policy = RoutePolicyScript.new()
	var road_short := {
		"id": &"road-short",
		"segments": [{"surface": RoutePolicyScript.ROAD, "length_m": 20.0}],
	}
	var footway_reasonable := {
		"id": &"footway-reasonable",
		"segments": [{"surface": RoutePolicyScript.FOOTWAY, "length_m": 28.0}],
	}
	var chosen: Dictionary = policy.choose_route([road_short, footway_reasonable])
	_assert(StringName(chosen.get("id", &"")) == &"footway-reasonable", "ordinary pedestrian policy prefers a reasonable footway over a shorter roadway")

	var road_only: Dictionary = policy.choose_route([road_short])
	_assert(StringName(road_only.get("id", &"")) == &"road-short", "road remains usable when it is the only candidate connection")

	var blocked_footway := {
		"id": &"blocked-footway",
		"segments": [{"surface": RoutePolicyScript.FOOTWAY, "length_m": 10.0, "blocked": true}],
	}
	var safe_road := {
		"id": &"safe-road",
		"segments": [{"surface": RoutePolicyScript.ROAD, "length_m": 24.0}],
	}
	var blocked_choice: Dictionary = policy.choose_route([blocked_footway, safe_road])
	_assert(StringName(blocked_choice.get("id", &"")) == &"safe-road", "blocked geometry is not selected even when its surface is preferred")

	var no_sidewalk_choice: Dictionary = policy.choose_route([{
		"id": &"osm-road-fallback",
		"segments": [{"surface": RoutePolicyScript.ROAD, "length_m": 35.0}],
	}])
	_assert(StringName(no_sidewalk_choice.get("id", &"")) == &"osm-road-fallback", "missing sidewalk/footway data does not make an area unroutable")
	_assert(PersonMovementModelScript.new().can_traverse_surface(PersonMovementModelScript.ROAD), "Person physical rules keep roads traversable independently of pedestrian preference")
	_assert(policy.surface_weight(RoutePolicyScript.ROAD) > policy.surface_weight(RoutePolicyScript.FOOTWAY), "pedestrian preference discourages road walking without changing Person physics")

func _test_deterministic_ai_and_danger_response() -> void:
	var ai = PedestrianAIScript.new()
	var candidates := [
		{"id": &"a", "segments": [{"surface": RoutePolicyScript.PATH, "length_m": 40.0}]},
		{"id": &"b", "segments": [{"surface": RoutePolicyScript.ROAD, "length_m": 12.0}]},
	]
	var first: Dictionary = ai.choose_route(candidates)
	var second: Dictionary = ai.choose_route(candidates)
	_assert(first == second, "fixed pedestrian route input produces deterministic output")

	var walking_intent = ai.movement_intent(Vector3.ZERO, Vector3(10.0, 0.0, 0.0), 20.0)
	_assert(walking_intent.direction.x > 0.9, "pedestrian AI produces generic movement intent toward destination")
	var danger_intent = ai.movement_intent(Vector3.ZERO, Vector3(10.0, 0.0, 0.0), 1.0)
	_assert(danger_intent.direction.is_zero_approx(), "nearby vehicle danger causes simple safe wait instead of suicidal default movement")

func _test_lightweight_motion() -> void:
	var ai = PedestrianAIScript.new()
	var agent_a = PedestrianAgentScript.new(&"npc-a", Vector3.ZERO)
	var agent_b = PedestrianAgentScript.new(&"npc-b", Vector3.ZERO)
	var intent_a = ai.movement_intent(agent_a.position, Vector3(10.0, 0.0, 0.0))
	var intent_b = ai.movement_intent(agent_b.position, Vector3(10.0, 0.0, 0.0))
	for _step in 10:
		agent_a.advance(intent_a, 0.1)
		agent_b.advance(intent_b, 0.1)
	_assert(agent_a.position.is_equal_approx(agent_b.position), "lightweight pedestrian motion is deterministic for fixed input")
	_assert(agent_a.position.x > 0.0, "far logical pedestrian can move without a full Godot Person")

func _test_population_promotion_and_demotion() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var population = PedestrianPopulationScript.new()
	population.promote_distance_m = 10.0
	population.demote_distance_m = 15.0
	root.add_child(population)

	var near_agent = PedestrianAgentScript.new(&"near-npc", Vector3(5.0, 0.0, 0.0))
	near_agent.destination = Vector3(100.0, 0.0, 0.0)
	near_agent.route_index = 3
	near_agent.waiting_for_vehicle = true
	var far_agent = PedestrianAgentScript.new(&"far-npc", Vector3(50.0, 0.0, 0.0))
	_assert(population.add_agent(near_agent), "near NPC logical agent is accepted")
	_assert(population.add_agent(far_agent), "far NPC logical agent is accepted independently of player Person")
	_assert(not population.add_agent(PedestrianAgentScript.new(&"near-npc", Vector3.ZERO)), "duplicate pedestrian identity is rejected")

	population.update_relevance(Vector3.ZERO)
	await process_frame
	_assert(population.full_count() == 1, "near relevant pedestrian promotes to one full Person")
	_assert(population.lightweight_count() == 1, "distant pedestrian remains lightweight")
	var full_person = population.full_person(&"near-npc")
	_assert(full_person != null, "promoted Person instance is available")
	if full_person != null:
		full_person.gravity_mps2 = 0.0
		_assert(StringName(full_person.person_id) == &"near-npc", "promotion preserves Person identity")
		_assert(full_person.global_position.is_equal_approx(Vector3(5.0, 0.0, 0.0)), "promotion preserves logical position")
		_assert(full_person.get_node_or_null("PlayerPersonController") == null, "NPC full Person exists independently of the player controller")
		full_person.global_position = Vector3(20.0, 0.0, 0.0)
		full_person.rotation.y = 0.75

	population.update_relevance(Vector3.ZERO)
	await process_frame
	_assert(not population.is_promoted(&"near-npc"), "distant full Person demotes back to lightweight state")
	_assert(near_agent.person_id == &"near-npc", "demotion preserves identity")
	_assert(near_agent.position.is_equal_approx(Vector3(20.0, 0.0, 0.0)), "demotion captures current full Person position")
	_assert(is_equal_approx(near_agent.facing_rad, 0.75), "demotion captures meaningful facing state")
	_assert(near_agent.destination.is_equal_approx(Vector3(100.0, 0.0, 0.0)), "promotion/demotion preserves pedestrian destination state")
	_assert(near_agent.route_index == 3 and near_agent.waiting_for_vehicle, "promotion/demotion preserves route/waiting logical state")

	population.update_relevance(Vector3(20.0, 0.0, 0.0))
	await process_frame
	var promoted_again = population.full_person(&"near-npc")
	_assert(promoted_again != null and StringName(promoted_again.person_id) == &"near-npc", "same logical pedestrian can promote again with the same identity")

	root.queue_free()
	await process_frame

func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
