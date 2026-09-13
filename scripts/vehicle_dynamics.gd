class_name VehicleDynamics
extends RefCounted

## Integrates deterministic flat-world vehicle motion from generic control intent.
##
## Dependencies:
## - Mutates VehicleState-compatible data only; has no SceneTree, rendering, input, routing, traffic, or police dependency.
## - Uses SI units plus explicit vehicle, tire, energy and surface data supplied by the adapter/domain layer.

const GRAVITY_MPS2: float = 9.81
const MIN_TIRE_CONDITION: float = 0.20

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
	surface_modifiers: Dictionary = {},
	physical_profile: Dictionary = {}
) -> void:
	if delta_s <= 0.0:
		return

	_initialize_resource_state(state, physical_profile)
	if not state.travel_heading_initialized:
		state.travel_heading_rad = state.heading_rad
		state.travel_heading_initialized = true

	var speed_factor: float = clampf(float(surface_modifiers.get("speed_factor", 1.0)), 0.01, 1.0)
	var acceleration_factor: float = clampf(float(surface_modifiers.get("acceleration_factor", 1.0)), 0.0, 1.0)
	var braking_factor: float = clampf(float(surface_modifiers.get("braking_factor", 1.0)), 0.0, 1.0)
	var steering_factor: float = clampf(float(surface_modifiers.get("steering_factor", 1.0)), 0.0, 1.0)
	var surface_grip_factor: float = clampf(float(surface_modifiers.get("grip_factor", steering_factor)), 0.05, 2.0)
	var overspeed_deceleration_mps2: float = maxf(0.0, float(surface_modifiers.get("overspeed_deceleration_mps2", 0.0)))
	var effective_max_speed_mps: float = maxf(0.0, max_speed_mps * speed_factor)
	var effective_reverse_speed_mps: float = maxf(0.0, max_reverse_speed_mps * speed_factor)
	var effective_max_steer_degrees: float = max_steer_degrees * steering_factor

	var safe_throttle: float = clampf(throttle, -1.0, 1.0)
	var safe_brake: float = clampf(brake, 0.0, 1.0)
	var safe_steering: float = clampf(steering, -1.0, 1.0)
	var energy_available: bool = state.energy_capacity <= 0.0 or state.energy_remaining > 0.000001
	if not energy_available:
		safe_throttle = 0.0

	var mass_kg: float = maxf(1.0, float(physical_profile.get("mass_kg", 1500.0)))
	var drive_force_n: float = maxf(0.0, float(physical_profile.get("drive_force_n", acceleration_mps2 * mass_kg))) * acceleration_factor
	var brake_force_n: float = maxf(0.0, float(physical_profile.get("brake_force_n", braking_mps2 * mass_kg))) * braking_factor
	var tire_grip_coefficient: float = maxf(0.05, float(physical_profile.get("tire_grip_coefficient", 1.0)))
	var tire_factor: float = 0.30 + 0.70 * clampf(state.tire_condition, MIN_TIRE_CONDITION, 1.0)
	var available_grip_accel_mps2: float = GRAVITY_MPS2 * tire_grip_coefficient * surface_grip_factor * tire_factor

	if state.speed_mps > effective_max_speed_mps and overspeed_deceleration_mps2 > 0.0:
		state.speed_mps = move_toward(state.speed_mps, effective_max_speed_mps, overspeed_deceleration_mps2 * delta_s)
	elif state.speed_mps < -effective_reverse_speed_mps and overspeed_deceleration_mps2 > 0.0:
		state.speed_mps = move_toward(state.speed_mps, -effective_reverse_speed_mps, overspeed_deceleration_mps2 * delta_s)

	var wheelbase_m: float = maxf(length_m * 0.6, 0.8)
	var steer_angle_rad: float = deg_to_rad(effective_max_steer_degrees) * safe_steering
	var requested_lateral_accel_mps2: float = 0.0
	if absf(state.speed_mps) >= 0.05 and absf(safe_steering) >= 0.001:
		requested_lateral_accel_mps2 = state.speed_mps * state.speed_mps / wheelbase_m * tan(steer_angle_rad)

	var requested_longitudinal_accel_mps2: float = _requested_longitudinal_accel(
		state.speed_mps,
		safe_throttle,
		safe_brake,
		drive_force_n / mass_kg,
		brake_force_n / mass_kg
	)
	var demand_ratio: float = sqrt(
		pow(requested_longitudinal_accel_mps2 / available_grip_accel_mps2, 2.0)
		+ pow(requested_lateral_accel_mps2 / available_grip_accel_mps2, 2.0)
	)
	var grip_scale: float = 1.0 / maxf(1.0, demand_ratio)
	var actual_longitudinal_accel_mps2: float = requested_longitudinal_accel_mps2 * grip_scale
	var actual_lateral_accel_mps2: float = requested_lateral_accel_mps2 * grip_scale

	var previous_speed_mps: float = state.speed_mps
	state.speed_mps += actual_longitudinal_accel_mps2 * delta_s
	if _is_braking_toward_zero(previous_speed_mps, state.speed_mps, safe_brake, safe_throttle):
		state.speed_mps = 0.0
	elif actual_longitudinal_accel_mps2 > 0.0 and previous_speed_mps <= effective_max_speed_mps and state.speed_mps > effective_max_speed_mps:
		state.speed_mps = effective_max_speed_mps
	elif actual_longitudinal_accel_mps2 < 0.0 and previous_speed_mps >= -effective_reverse_speed_mps and state.speed_mps < -effective_reverse_speed_mps:
		state.speed_mps = -effective_reverse_speed_mps

	_integrate_heading_and_slip(
		state,
		requested_lateral_accel_mps2,
		actual_lateral_accel_mps2,
		available_grip_accel_mps2,
		mass_kg,
		surface_grip_factor,
		tire_factor,
		physical_profile,
		delta_s
	)

	if absf(state.speed_mps) >= 0.001:
		state.x_m += -sin(state.travel_heading_rad) * state.speed_mps * delta_s
		state.z_m += -cos(state.travel_heading_rad) * state.speed_mps * delta_s

	state.last_longitudinal_accel_mps2 = actual_longitudinal_accel_mps2
	state.last_lateral_accel_mps2 = actual_lateral_accel_mps2
	state.last_grip_usage = demand_ratio
	state.last_slip_angle_rad = wrapf(state.heading_rad - state.travel_heading_rad, -PI, PI)
	_apply_tire_wear(state, demand_ratio, physical_profile, delta_s)
	_consume_energy(state, safe_throttle, actual_longitudinal_accel_mps2, mass_kg, physical_profile, delta_s)

func _requested_longitudinal_accel(
	speed_mps: float,
	throttle: float,
	brake: float,
	drive_accel_mps2: float,
	brake_accel_mps2: float
) -> float:
	if brake > 0.0:
		if speed_mps > 0.001:
			return -brake_accel_mps2 * brake
		if speed_mps < -0.001:
			return brake_accel_mps2 * brake
		return 0.0
	if throttle > 0.0:
		return drive_accel_mps2 * throttle
	if throttle < 0.0:
		if speed_mps > 0.001:
			return -brake_accel_mps2 * -throttle
		return -drive_accel_mps2 * -throttle
	return 0.0

func _is_braking_toward_zero(previous_speed_mps: float, next_speed_mps: float, brake: float, throttle: float) -> bool:
	var braking: bool = brake > 0.0 or (throttle < 0.0 and previous_speed_mps > 0.0)
	if not braking:
		return false
	return (previous_speed_mps > 0.0 and next_speed_mps < 0.0) or (previous_speed_mps < 0.0 and next_speed_mps > 0.0)

func _integrate_heading_and_slip(
	state,
	requested_lateral_accel_mps2: float,
	actual_lateral_accel_mps2: float,
	available_grip_accel_mps2: float,
	mass_kg: float,
	surface_grip_factor: float,
	tire_factor: float,
	physical_profile: Dictionary,
	delta_s: float
) -> void:
	var abs_speed_mps: float = absf(state.speed_mps)
	if abs_speed_mps < 0.05:
		state.yaw_rate_rps = move_toward(state.yaw_rate_rps, 0.0, 6.0 * delta_s)
		state.travel_heading_rad = state.heading_rad
		return

	var signed_speed_mps: float = state.speed_mps
	var requested_yaw_rate_rps: float = requested_lateral_accel_mps2 / signed_speed_mps
	var yaw_grip_ratio: float = clampf(float(physical_profile.get("yaw_grip_ratio", 1.25)), 0.7, 2.0)
	var yaw_limit_rps: float = available_grip_accel_mps2 * yaw_grip_ratio / abs_speed_mps
	var target_yaw_rate_rps: float = clampf(requested_yaw_rate_rps, -yaw_limit_rps, yaw_limit_rps)
	var mass_response_factor: float = clampf(pow(1500.0 / mass_kg, 0.25), 0.55, 1.60)
	var yaw_response_rps2: float = maxf(0.1, float(physical_profile.get("yaw_response_rps2", 4.0))) * surface_grip_factor * tire_factor * mass_response_factor
	state.yaw_rate_rps = move_toward(state.yaw_rate_rps, target_yaw_rate_rps, yaw_response_rps2 * delta_s)
	state.heading_rad = wrapf(state.heading_rad + state.yaw_rate_rps * delta_s, -PI, PI)

	var travel_turn_rate_rps: float = actual_lateral_accel_mps2 / signed_speed_mps
	state.travel_heading_rad = wrapf(state.travel_heading_rad + travel_turn_rate_rps * delta_s, -PI, PI)

	var slip_angle_rad: float = wrapf(state.heading_rad - state.travel_heading_rad, -PI, PI)
	var lateral_ratio: float = absf(requested_lateral_accel_mps2) / maxf(available_grip_accel_mps2, 0.001)
	if lateral_ratio < 0.80:
		var recovery_rate_rps: float = available_grip_accel_mps2 / maxf(abs_speed_mps, 1.0)
		var correction_rad: float = clampf(slip_angle_rad, -recovery_rate_rps * delta_s, recovery_rate_rps * delta_s)
		state.travel_heading_rad = wrapf(state.travel_heading_rad + correction_rad, -PI, PI)

func _initialize_resource_state(state, physical_profile: Dictionary) -> void:
	var capacity: float = maxf(0.0, float(physical_profile.get("energy_capacity", 0.0)))
	if state.energy_capacity <= 0.0 and capacity > 0.0:
		state.energy_capacity = capacity
		state.energy_remaining = capacity
	if state.energy_type == &"" and physical_profile.has("energy_type"):
		state.energy_type = StringName(str(physical_profile.get("energy_type", "")))
	state.tire_condition = clampf(state.tire_condition, MIN_TIRE_CONDITION, 1.0)

func _consume_energy(
	state,
	throttle: float,
	actual_longitudinal_accel_mps2: float,
	mass_kg: float,
	physical_profile: Dictionary,
	delta_s: float
) -> void:
	if state.energy_capacity <= 0.0 or state.energy_remaining <= 0.0:
		return
	var energy_type: StringName = state.energy_type
	if energy_type == &"" or energy_type == &"none":
		return

	var speed_mps: float = absf(state.speed_mps)
	var traction_power_w: float = 0.0
	if absf(throttle) > 0.001:
		traction_power_w = absf(actual_longitudinal_accel_mps2) * mass_kg * speed_mps
	var rolling_coefficient: float = maxf(0.0, float(physical_profile.get("rolling_resistance_coefficient", 0.012)))
	var aero_factor: float = maxf(0.0, float(physical_profile.get("aero_drag_factor", 0.38)))
	var road_load_w: float = 0.0
	if absf(throttle) > 0.001:
		road_load_w = rolling_coefficient * mass_kg * GRAVITY_MPS2 * speed_mps + aero_factor * pow(speed_mps, 3.0)
	var mechanical_kwh: float = (traction_power_w + road_load_w) * delta_s / 3600000.0
	var consumed: float = 0.0
	match energy_type:
		&"electric":
			consumed = mechanical_kwh / 0.90 + 0.000002 * delta_s
		&"diesel":
			consumed = mechanical_kwh / (9.8 * 0.34) + 0.00014 * delta_s
		&"petrol":
			consumed = mechanical_kwh / (8.9 * 0.28) + 0.00018 * delta_s
		_:
			return
	state.energy_remaining = maxf(0.0, state.energy_remaining - consumed)

func _apply_tire_wear(state, grip_usage: float, physical_profile: Dictionary, delta_s: float) -> void:
	var wear_rate: float = maxf(0.0, float(physical_profile.get("tire_wear_rate", 0.00008)))
	if wear_rate <= 0.0:
		return
	var slip_angle_rad: float = absf(wrapf(state.heading_rad - state.travel_heading_rad, -PI, PI))
	var hard_grip: float = maxf(0.0, grip_usage - 0.75)
	var slip_load: float = maxf(0.0, slip_angle_rad - 0.04) / 0.25
	var speed_factor: float = clampf(absf(state.speed_mps) / 20.0, 0.25, 2.5)
	var wear: float = wear_rate * (hard_grip * hard_grip + slip_load * slip_load) * speed_factor * delta_s
	state.tire_condition = clampf(state.tire_condition - wear, MIN_TIRE_CONDITION, 1.0)
