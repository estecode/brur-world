class_name PolicePursuitRefreshPolicy
extends RefCounted

## Decides when one pursuer should refresh its intercept route.
##
## Dependencies:
## - Uses caller-provided time, route remainder and predicted target only.
## - Does not calculate routes, drive vehicles or read SceneTree state.

var fresh_interval_s: float = 0.75
var stale_interval_s: float = 2.5
var refresh_remaining_distance_m: float = 35.0
var target_shift_m: float = 12.0

func should_refresh(now_s: float, last_refresh_s: float, remaining_distance_m: float, previous_target: Vector2, prediction: Dictionary) -> bool:
	if prediction.is_empty():
		return false
	if last_refresh_s < 0.0:
		return true
	if remaining_distance_m >= 0.0 and remaining_distance_m <= refresh_remaining_distance_m:
		return true
	var interval := stale_interval_s if bool(prediction.get("stale", false)) else fresh_interval_s
	if now_s - last_refresh_s >= interval:
		return true
	var target: Vector2 = prediction.get("position", previous_target)
	return previous_target.is_finite() and target.is_finite() and previous_target.distance_to(target) >= target_shift_m
