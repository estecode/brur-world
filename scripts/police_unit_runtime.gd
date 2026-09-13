class_name PoliceUnitRuntime
extends Node

## Adapts one police unit to explicit player observation and offence evaluation.
##
## Dependencies:
## - Police/player Vehicle nodes expose position, heading and actual speed.
## - RoadSpeedLimitQuery is injected and remains owner of road-limit lookup.
## - PoliceObservationStore owns shared observed knowledge; PoliceUnitLogic owns state transitions.

const PoliceObservationPolicyScript = preload("res://scripts/police_observation_policy.gd")
const SpeedingOffenceDetectorScript = preload("res://scripts/speeding_offence_detector.gd")
const PoliceUnitLogicScript = preload("res://scripts/police_unit_logic.gd")

var unit_id := ""
var police_vehicle: Node3D
var target_vehicle: Node3D
var road_speed_query
var observation_store
var observation_policy = PoliceObservationPolicyScript.new()
var logic = PoliceUnitLogicScript.new()

func setup(id: String, police_node: Node3D, target_node: Node3D, speed_query, shared_observation_store) -> bool:
	unit_id = id.strip_edges(); police_vehicle = police_node; target_vehicle = target_node; road_speed_query = speed_query; observation_store = shared_observation_store
	if unit_id.is_empty() or police_vehicle == null or target_vehicle == null or road_speed_query == null or observation_store == null:
		return false
	logic.add_detector(SpeedingOffenceDetectorScript.new())
	return true

func sample(now_s: float, line_of_sight_clear: bool = true) -> Dictionary:
	if police_vehicle == null or target_vehicle == null:
		return {}
	var observer := Vector2(police_vehicle.global_position.x, police_vehicle.global_position.z)
	var target := Vector2(target_vehicle.global_position.x, target_vehicle.global_position.z)
	if not observation_policy.can_observe(observer, float(police_vehicle.call("heading_rad")), target, line_of_sight_clear):
		return {}
	var target_speed := float(target_vehicle.call("speed_mps"))
	observation_store.publish(target, now_s, rad_to_deg(float(target_vehicle.call("heading_rad"))), target_speed, unit_id, true)
	var observation: Dictionary = observation_store.get_latest(now_s)
	if str(observation.get("source_unit_id", "")) != unit_id:
		return {}
	var speed_limit_value: Variant = road_speed_query.call("speed_limit_kmh_at", target_vehicle.global_position)
	if speed_limit_value == null:
		return {}
	return logic.update_from_observation(observation, float(speed_limit_value))

func step(delta: float, target_complied: bool = false) -> void:
	logic.step(delta, target_complied)

func consume_pursuit_handoff() -> Dictionary:
	return logic.consume_pursuit_handoff()
