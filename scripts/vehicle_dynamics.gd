class_name VehicleDynamics
extends RefCounted

## Integrates deterministic flat-world vehicle motion from generic control intent.
##
## Dependencies:
## - Mutates VehicleState-compatible data only; has no SceneTree, rendering, input, routing, traffic, or police dependency.
## - Uses real SI units plus explicit vehicle limits and surface modifiers supplied by the adapter/domain layer.

func step(
	state,
	throttle: float,
	brake: float,
	steering: float,
	delta_s: float,
	length_m: float,
	max_speed_mps: float,
	acceleration_mps2: float,
	braking_mps2: float,
	max_reverse_speed_mps: float,
	max_steer_degrees: float,
	surface_modifiers: Dictionary = {}
) -> void:
	if delta_s <= 0.0:
		return

	var speed_factor: float = clampf(float(surface_modifiers.get("speed_factor", 1.0)), 0.01, 1.0)
	var acceleration_factor: float = clampf(float(surface_modifiers.get("acceleration_factor", 1.0)), 0.0, 1.0)
	var braking_factor: float = clampf(float(surface_modifiers.get("braking_factor", 1.0)), 0.0, 1.0)
	var steering_factor: float = clampf(float(surface_modifiers.get("steering_factor", 1.0)), 0.0, 1.0)
	var overspeed_deceleration_mps2: float = maxf(0.0, float(surface_modifiers.get("overspeed_deceleration_mps2", 0.0)))
	var effective_max_speed_mps: float = max_speed_mps * speed_factor
	var effective_reverse_speed_mps: float = max_reverse_speed_mps * speed_factor
	var effective_acceleration_mps2: float = acceleration_mps2 * acceleration_factor
	var effective_braking_mps2: float = braking_mps2 * braking_factor
	var effective_max_steer_degrees: float = max_steer_degrees * steering_factor

	if state.speed_mps > effective_max_speed_mps and overspeed_deceleration_mps2 > 0.0:
		state.speed_mps = move_toward(state.speed_mps, effective_max_speed_mps, overspeed_deceleration_mps2 * delta_s)
	elif state.speed_mps < -effective_reverse_speed_mps and overspeed_deceleration_mps2 > 0.0:
		state.speed_mps = move_toward(state.speed_mps, -effective_reverse_speed_mps, overspeed_deceleration_mps2 * delta_s)

	var safe_throttle: float = clampf(throttle, -1.0, 1.0)
	var safe_brake: float = clampf(brake, 0.0, 1.0)
	var safe_steering: float = clampf(steering, -1.0, 1.0)

	if safe_brake > 0.0:
		state.speed_mps = move_toward(state.speed_mps, 0.0, effective_braking_mps2 * safe_brake * delta_s)
	elif safe_throttle > 0.0:
		state.speed_mps = minf(effective_max_speed_mps, state.speed_mps + effective_acceleration_mps2 * safe_throttle * delta_s)
	elif safe_throttle < 0.0:
		if state.speed_mps > 0.0:
			state.speed_mps = move_toward(state.speed_mps, 0.0, effective_braking_mps2 * -safe_throttle * delta_s)
		else:
			state.speed_mps = maxf(-effective_reverse_speed_mps, state.speed_mps - effective_acceleration_mps2 * -safe_throttle * delta_s)

	if absf(state.speed_mps) >= 0.05 and absf(safe_steering) >= 0.001:
		var wheelbase_m: float = maxf(length_m * 0.6, 0.8)
		var steer_angle_rad: float = deg_to_rad(effective_max_steer_degrees) * safe_steering
		state.heading_rad += state.speed_mps / wheelbase_m * tan(steer_angle_rad) * delta_s
		state.heading_rad = wrapf(state.heading_rad, -PI, PI)

	if absf(state.speed_mps) < 0.001:
		return
	state.x_m += -sin(state.heading_rad) * state.speed_mps * delta_s
	state.z_m += -cos(state.heading_rad) * state.speed_mps * delta_s
