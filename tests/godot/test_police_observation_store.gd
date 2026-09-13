extends SceneTree

## Headless deterministic tests for shared non-omniscient police observations.
##
## Dependencies:
## - scripts/police_observation_store.gd only.

const PoliceObservationStoreScript = preload("res://scripts/police_observation_store.gd")

func _init() -> void:
	_test_publish_and_share()
	_test_age_without_omniscient_updates()
	_test_older_observations_do_not_replace_newer_knowledge()
	_test_future_source_contract()
	print("godot police-observation-store tests: OK")
	quit(0)

func _test_publish_and_share() -> void:
	var store = PoliceObservationStoreScript.new(10.0)
	_assert(not store.has_observation(), "store starts empty")
	_assert(store.publish(Vector2(100.0, 200.0), 50.0, 725.0, 22.0, "patrol-12"), "observing unit can publish")

	var unit_a: Dictionary = store.get_latest(52.0)
	var unit_b: Dictionary = store.get_latest(52.0)
	_assert(unit_a["position"] == Vector2(100.0, 200.0), "published position is shared")
	_assert(unit_b["position"] == unit_a["position"], "another unit reads the same shared observation")
	_assert(is_equal_approx(float(unit_a["heading_deg"]), 5.0), "heading is normalized")
	_assert(is_equal_approx(float(unit_a["speed_mps"]), 22.0), "observed speed is retained")
	_assert(unit_a["source_unit_id"] == "patrol-12", "source unit is retained")
	_assert(bool(unit_a["confirmed"]), "direct observation is marked confirmed")
	_assert(bool(unit_a["current"]), "fresh confirmed observation is current")
	_assert(not bool(unit_a["stale"]), "fresh observation is not stale")

	unit_a["position"] = Vector2.ZERO
	_assert(store.get_latest(52.0)["position"] == Vector2(100.0, 200.0), "readers cannot mutate stored knowledge")

func _test_age_without_omniscient_updates() -> void:
	var store = PoliceObservationStoreScript.new(5.0)
	store.publish(Vector2(10.0, 20.0), 100.0, 90.0, 15.0, "patrol-1")
	var fresh: Dictionary = store.get_latest(104.0)
	var stale: Dictionary = store.get_latest(106.0)
	_assert(is_equal_approx(float(fresh["age_s"]), 4.0), "observation age is available")
	_assert(is_equal_approx(float(stale["age_s"]), 6.0), "age increases from caller time only")
	_assert(bool(stale["stale"]), "old knowledge becomes stale")
	_assert(not bool(stale["current"]), "stale knowledge is no longer current")
	_assert(stale["position"] == Vector2(10.0, 20.0), "position freezes when nobody publishes a new observation")

func _test_older_observations_do_not_replace_newer_knowledge() -> void:
	var store = PoliceObservationStoreScript.new()
	_assert(store.publish(Vector2(20.0, 30.0), 20.0, 180.0, 12.0, "patrol-new"), "new observation is accepted")
	_assert(not store.publish(Vector2(1.0, 1.0), 19.0, 0.0, 99.0, "patrol-delayed"), "older delayed observation is rejected")
	var latest: Dictionary = store.get_latest(21.0)
	_assert(latest["position"] == Vector2(20.0, 30.0), "latest shared knowledge does not move backwards in time")
	_assert(latest["source_unit_id"] == "patrol-new", "newest source remains authoritative")
	_assert(not store.publish(Vector2.ZERO, 22.0, 0.0, 0.0, "   "), "anonymous sources cannot publish")

func _test_future_source_contract() -> void:
	var store = PoliceObservationStoreScript.new()
	_assert(store.publish(Vector2(300.0, 400.0), 200.0, -90.0, 30.0, "helicopter-alpha", false), "non-patrol source can use the same publish contract")
	var latest: Dictionary = store.get_latest(201.0)
	_assert(latest["source_unit_id"] == "helicopter-alpha", "source contract is unit-agnostic")
	_assert(is_equal_approx(float(latest["heading_deg"]), 270.0), "estimated heading uses the same observation contract")
	_assert(not bool(latest["confirmed"]), "estimated observation can be explicitly unconfirmed")
	_assert(not bool(latest["current"]), "unconfirmed knowledge is not reported as current/confirmed")

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("police-observation-store test failed: " + message)
	quit(1)
