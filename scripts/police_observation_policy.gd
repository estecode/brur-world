class_name PoliceObservationPolicy
extends RefCounted

## Decides whether a police unit can directly observe a target from caller-provided spatial state.
##
## Dependencies:
## - Pure police-domain policy using positions/headings supplied by composition.
## - Does not read player nodes, routing, rendering, physics queries or global state.

var max_range_m: float = 120.0
var field_of_view_deg: float = 140.0

func can_observe(observer_position: Vector2, observer_heading_rad: float, target_position: Vector2, line_of_sight_clear: bool = true) -> bool:
	if not line_of_sight_clear:
		return false
	var delta := target_position - observer_position
	if delta.length_squared() > max_range_m * max_range_m:
		return false
	if delta.length_squared() <= 0.0001:
		return true
	var forward := Vector2(sin(observer_heading_rad), cos(observer_heading_rad))
	var angle := absf(forward.angle_to(delta.normalized()))
	return angle <= deg_to_rad(field_of_view_deg * 0.5)
