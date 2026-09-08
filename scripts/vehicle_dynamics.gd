class_name VehicleDynamics
extends RefCounted

## Integrates deterministic flat-road vehicle motion from generic control intent.
##
## Dependencies:
## - Mutates VehicleState only; has no SceneTree, rendering, input, routing, traffic, or police dependency.
## - Uses real SI units and explicit vehicle limits supplied by the adapter/configuration layer.

static func step(
	state: VehicleState,
	throttle: float,
	brake: float,
	steering: float,
	delta_s: float,
	length_m: float,
	max_speed_mps: float,
	acceleration_mps2: float,
	braking_mps2: float,
	max_reverse_speed_mps: float,
	max_steer_degrees: float
) -> void:
	if delta_s <= 0.0:
		return

	var safe_throttle: float = clampf(throttle, -1.0, 1.0)
	var safe_brake: float = clampf(brake, 0.0, 1.0)
	var safe_steering: float = clampf(steering, -1.0, 1.0)

	if safe_brake > 0.0:
		state.speed_mps = move_toward(state.speed_mps, 0.0, braking_mps2 * safe_brake * delta_s)
	elif safe_throttle > 0.0:
		state.speed_mps = minf(max_speed_mps, state.speed_mps + acceleration_mps2 * safe_throttle * delta_s)
	elif safe_throttle < 0.0:
		if state.speed_mps > 0.0:
			state.speed_mps = move_toward(state.speed_mps, 0.0, braking_mps2 * -safe_throttle * delta_s)
		else:
			state.speed_mps = maxf(-max_reverse_speed_mps, state.speed_mps - acceleration_mps2 * -safe_throttle * delta_s)

	if absf(state.speed_mps) >= 0.05 and absf(safe_steering) >= 0.001:
		var wheelbase_m: float = maxf(length_m * 0.6, 0.8)
		var steer_angle_rad: float = deg_to_rad(max_steer_degrees) * safe_steering
		state.heading_rad += state.speed_mps / wheelbase_m * tan(steer_angle_rad) * delta_s
		state.heading_rad = wrapf(state.heading_rad, -PI, PI)

	if absf(state.speed_mps) < 0.001:
		return
	state.x_m += -sin(state.heading_rad) * state.speed_mps * delta_s
	state.z_m += -cos(state.heading_rad) * state.speed_mps * delta_s
