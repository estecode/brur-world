class_name PolicePursuitPredictor
extends RefCounted

## Predicts a short pursuit target from the latest shared police observation.
##
## Dependencies:
## - Consumes PoliceObservationStore-shaped dictionaries.
## - Delegates road-constrained advancement to the injected routing owner.
## - Owns no road graph, vehicle state, SceneTree or presentation.

var min_horizon_s: float = 1.5
var max_horizon_s: float = 4.0
var speed_horizon_factor: float = 0.12

func predict(observation: Dictionary, routing_owner) -> Dictionary:
	if observation.is_empty() or routing_owner == null:
		return {}
	var position: Vector2 = observation.get("position", Vector2(INF, INF))
	if not position.is_finite():
		return {}
	var stale := bool(observation.get("stale", false)) or not bool(observation.get("current", false))
	if stale:
		return {
			"position": position,
			"predicted": false,
			"stale": true,
			"source_timestamp_s": float(observation.get("timestamp_s", 0.0)),
		}
	if not routing_owner.has_method("advance_along_road"):
		return {}
	var speed_mps := maxf(0.0, float(observation.get("speed_mps", 0.0)))
	var horizon_s := clampf(min_horizon_s + speed_mps * speed_horizon_factor, min_horizon_s, max_horizon_s)
	var distance_m := speed_mps * horizon_s
	var heading_deg := float(observation.get("heading_deg", 0.0))
	var advanced: Variant = routing_owner.call("advance_along_road", position, heading_deg, distance_m)
	if not advanced is Vector2 or not (advanced as Vector2).is_finite():
		return {}
	return {
		"position": advanced,
		"predicted": distance_m > 0.01,
		"stale": false,
		"horizon_s": horizon_s,
		"distance_m": distance_m,
		"source_timestamp_s": float(observation.get("timestamp_s", 0.0)),
	}
