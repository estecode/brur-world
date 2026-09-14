class_name PolicePursuitCoordinator
extends RefCounted

## Coordinates one police unit's pursuit target and route refresh without owning routing or driving.
##
## Dependencies:
## - Uses PolicePursuitPredictor and PolicePursuitRefreshPolicy.
## - Calls an injected routing owner for road-constrained prediction and route calculation.
## - Returns route data for a separate police driving adapter.

const PredictorScript = preload("res://scripts/police_pursuit_predictor.gd")
const RefreshPolicyScript = preload("res://scripts/police_pursuit_refresh_policy.gd")

var predictor = PredictorScript.new()
var refresh_policy = RefreshPolicyScript.new()
var routing_owner
var last_refresh_s: float = -1.0
var last_target: Vector2 = Vector2(INF, INF)
var route_request_count: int = 0

func setup(routing_api) -> bool:
	routing_owner = routing_api
	return routing_owner != null and routing_owner.has_method("route_to_intercept") and routing_owner.has_method("advance_along_road")

func update(unit_position: Vector2, observation: Dictionary, now_s: float, remaining_route_distance_m: float) -> Dictionary:
	if routing_owner == null or not unit_position.is_finite():
		return {}
	var prediction: Dictionary = predictor.predict(observation, routing_owner)
	if prediction.is_empty():
		return {}
	if not refresh_policy.should_refresh(now_s, last_refresh_s, remaining_route_distance_m, last_target, prediction):
		return {}
	var target: Vector2 = prediction.get("position", Vector2(INF, INF))
	if not target.is_finite():
		return {}
	var route_value: Variant = routing_owner.call("route_to_intercept", unit_position, target)
	if not route_value is Dictionary:
		return {}
	var route: Dictionary = route_value
	if not bool(route.get("success", false)):
		return {}
	last_refresh_s = now_s
	last_target = target
	route_request_count += 1
	var result := route.duplicate(true)
	result["intercept_target"] = target
	result["prediction_stale"] = bool(prediction.get("stale", false))
	result["source_timestamp_s"] = float(prediction.get("source_timestamp_s", 0.0))
	return result
