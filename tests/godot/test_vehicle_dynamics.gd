extends SceneTree

## Deterministic contract tests for portable vehicle physics, shared grip, resources and surface penalties.
## Dependencies: vehicle_state.gd, vehicle_dynamics.gd and vehicle_surface_policy.gd only.

const VehicleStateScript = preload("res://scripts/vehicle_state.gd")
const VehicleDynamicsScript = preload("res://scripts/vehicle_dynamics.gd")
const VehicleSurfacePolicyScript = preload("res://scripts/vehicle_surface_policy.gd")

var _dynamics = VehicleDynamicsScript.new()
var _surface_policy = VehicleSurfacePolicyScript.new()

func _init() -> void:
	_test_baseline_motion()
	_test_surface_contract()
	_test_determinism()
	_test_mass_and_force()
	_test_combined_grip_and_slip()
	_test_tire_condition_and_wear()
	_test_energy_contract()
	print("godot vehicle-dynamics tests: OK")
	quit(0)

func _test_baseline_motion() -> void:
	var forward = VehicleStateScript.new()
	_step(forward, 1.0, 0.0, 0.0, 1.0)
	_assert(_approx(forward.speed_mps, 3.0), "full throttle accelerates by configured force/mass")
	_assert(forward.z_m < 0.0, "forward throttle advances along the initial forward axis")

	var braking = VehicleStateScript.new()
	braking.speed_mps = 10.0
	_step(braking, 0.0, 1.0, 0.0, 1.0)
	_assert(_approx(braking.speed_mps, 3.0), "brake reduces speed toward zero")

	var reverse = VehicleStateScript.new()
	for _index in range(10):
		_step(reverse, -1.0, 0.0, 0.0, 1.0)
	_assert(_approx(reverse.speed_mps, -5.0), "reverse speed is bounded")

	var steering = VehicleStateScript.new()
	steering.speed_mps = 10.0
	_step(steering, 0.0, 0.0, 1.0, 0.5)
	_assert(absf(steering.heading_rad) > 0.01, "steering changes body heading while moving")
	_assert(absf(steering.last_lateral_accel_mps2) <= 9.81 + 0.001, "high-speed steering cannot create unlimited lateral acceleration")

	var limited = VehicleStateScript.new()
	limited.speed_mps = 35.5
	_step(limited, 1.0, 0.0, 5.0, 1.0)
	_assert(_approx(limited.speed_mps, 36.1), "forward speed limit is enforced for propulsion")

func _test_surface_contract() -> void:
	var road = VehicleStateScript.new()
	var off_road = VehicleStateScript.new()
	for _index in range(120):
		_step(road, 1.0, 0.0, 0.0, 1.0 / 60.0, VehicleSurfacePolicyScript.ROAD)
		_step(off_road, 1.0, 0.0, 0.0, 1.0 / 60.0, VehicleSurfacePolicyScript.OFF_ROAD)
	_assert(off_road.speed_mps < road.speed_mps, "off-road acceleration is worse under identical input")
	_assert(absf(off_road.z_m) < absf(road.z_m), "off-road vehicle covers less distance under identical input")

	var road_turn = VehicleStateScript.new()
	var off_road_turn = VehicleStateScript.new()
	road_turn.speed_mps = 10.0
	off_road_turn.speed_mps = 10.0
	_step(road_turn, 0.0, 0.0, 1.0, 0.5, VehicleSurfacePolicyScript.ROAD)
	_step(off_road_turn, 0.0, 0.0, 1.0, 0.5, VehicleSurfacePolicyScript.OFF_ROAD)
	_assert(absf(off_road_turn.last_lateral_accel_mps2) < absf(road_turn.last_lateral_accel_mps2), "off-road available cornering grip is lower")
	_assert(absf(off_road_turn.heading_rad) < absf(road_turn.heading_rad), "off-road body steering response is reduced")

	var transition = VehicleStateScript.new()
	transition.speed_mps = 30.0
	_step(transition, 0.0, 0.0, 0.0, 0.5, VehicleSurfacePolicyScript.OFF_ROAD)
	_assert(_approx(transition.speed_mps, 29.0), "entering off-road reduces overspeed continuously rather than snapping")
	var speed_before_return: float = transition.speed_mps
	_step(transition, 0.0, 0.0, 0.0, 0.5, VehicleSurfacePolicyScript.ROAD)
	_assert(_approx(transition.speed_mps, speed_before_return), "returning to road restores normal policy without resetting motion state")

	var road_brake_distance: float = _braking_distance(22.0, {"grip_factor": 1.0})
	var low_grip_brake_distance: float = _braking_distance(22.0, {"grip_factor": 0.35})
	_assert(low_grip_brake_distance > road_brake_distance * 1.5, "reduced grip materially increases braking distance")
	var fast_brake_distance: float = _braking_distance(30.0, {"grip_factor": 1.0})
	_assert(fast_brake_distance > road_brake_distance, "braking distance increases with initial speed")

func _test_determinism() -> void:
	var first = VehicleStateScript.new()
	var second = VehicleStateScript.new()
	for _index in range(240):
		_step(first, 0.72, 0.0, -0.35, 1.0 / 60.0, VehicleSurfacePolicyScript.OFF_ROAD)
		_step(second, 0.72, 0.0, -0.35, 1.0 / 60.0, VehicleSurfacePolicyScript.OFF_ROAD)
	_assert(_same_state(first, second), "same state input and dt produce identical physical/resource state")

func _test_mass_and_force() -> void:
	var light = VehicleStateScript.new()
	var heavy = VehicleStateScript.new()
	var shared_force := {
		"drive_force_n": 6000.0,
		"brake_force_n": 12000.0,
		"energy_type": "none",
		"energy_capacity": 0.0,
	}
	var light_profile: Dictionary = shared_force.duplicate(true)
	light_profile["mass_kg"] = 1000.0
	var heavy_profile: Dictionary = shared_force.duplicate(true)
	heavy_profile["mass_kg"] = 2000.0
	_step(light, 1.0, 0.0, 0.0, 1.0, VehicleSurfacePolicyScript.ROAD, light_profile)
	_step(heavy, 1.0, 0.0, 0.0, 1.0, VehicleSurfacePolicyScript.ROAD, heavy_profile)
	_assert(light.speed_mps > heavy.speed_mps * 1.8, "same drive force accelerates a lighter vehicle more strongly")

	light.speed_mps = 20.0
	heavy.speed_mps = 20.0
	_step(light, 0.0, 1.0, 0.0, 0.5, VehicleSurfacePolicyScript.ROAD, light_profile)
	_step(heavy, 0.0, 1.0, 0.0, 0.5, VehicleSurfacePolicyScript.ROAD, heavy_profile)
	_assert(light.speed_mps < heavy.speed_mps, "same brake force decelerates a lighter vehicle more strongly")

func _test_combined_grip_and_slip() -> void:
	var straight = VehicleStateScript.new()
	var corner = VehicleStateScript.new()
	straight.speed_mps = 20.0
	corner.speed_mps = 20.0
	_step(straight, 1.0, 0.0, 0.0, 0.1)
	_step(corner, 1.0, 0.0, 1.0, 0.1)
	_assert(corner.last_longitudinal_accel_mps2 < straight.last_longitudinal_accel_mps2, "hard throttle while cornering has less longitudinal grip than straight-line throttle")
	_assert(corner.last_grip_usage > 1.0, "combined demand records saturation beyond the available grip budget")
	var combined_actual: float = sqrt(pow(corner.last_longitudinal_accel_mps2, 2.0) + pow(corner.last_lateral_accel_mps2, 2.0))
	_assert(combined_actual <= 9.81 + 0.001, "combined longitudinal and lateral acceleration stays inside the road grip budget")

	var straight_brake = VehicleStateScript.new()
	var corner_brake = VehicleStateScript.new()
	straight_brake.speed_mps = 20.0
	corner_brake.speed_mps = 20.0
	_step(straight_brake, 0.0, 1.0, 0.0, 0.1)
	_step(corner_brake, 0.0, 1.0, 1.0, 0.1)
	_assert(absf(corner_brake.last_longitudinal_accel_mps2) < absf(straight_brake.last_longitudinal_accel_mps2), "hard braking while cornering shares the same finite grip budget")

	var saturated = VehicleStateScript.new()
	saturated.speed_mps = 25.0
	for _index in range(120):
		_step(saturated, 0.0, 1.0, 1.0, 1.0 / 60.0)
	var peak_slip: float = absf(saturated.last_slip_angle_rad)
	_assert(peak_slip > 0.08, "excess speed steering and braking create deterministic body/trajectory slip instead of perfect path adherence")
	var slip_before_recovery: float = absf(saturated.last_slip_angle_rad)
	for _index in range(180):
		_step(saturated, 0.0, 0.0, 0.0, 1.0 / 60.0)
	_assert(absf(saturated.last_slip_angle_rad) < slip_before_recovery, "reducing demand below the grip limit recovers slip without resetting state")

func _test_tire_condition_and_wear() -> void:
	var fresh = VehicleStateScript.new()
	var worn = VehicleStateScript.new()
	fresh.speed_mps = 18.0
	worn.speed_mps = 18.0
	worn.tire_condition = 0.45
	_step(fresh, 0.0, 0.0, 1.0, 0.1)
	_step(worn, 0.0, 0.0, 1.0, 0.1)
	_assert(absf(worn.last_lateral_accel_mps2) < absf(fresh.last_lateral_accel_mps2), "degraded tires reduce available cornering grip through the shared contract")

	var gentle = VehicleStateScript.new()
	var hard = VehicleStateScript.new()
	hard.speed_mps = 22.0
	for _index in range(600):
		_step(gentle, 0.25, 0.0, 0.0, 1.0 / 60.0)
		_step(hard, 1.0, 0.0, 1.0, 1.0 / 60.0)
	_assert(hard.tire_condition < gentle.tire_condition - 0.001, "hard saturated driving wears tires meaningfully more than ordinary driving")
	_assert(gentle.tire_condition > 0.999, "ordinary driving tire wear remains negligible")

func _test_energy_contract() -> void:
	for energy_type in ["petrol", "diesel", "electric"]:
		var state = VehicleStateScript.new()
		var profile: Dictionary = _default_profile()
		profile["energy_type"] = energy_type
		profile["energy_capacity"] = 60.0 if energy_type != "electric" else 75.0
		for _index in range(120):
			_step(state, 0.55, 0.0, 0.0, 1.0 / 60.0, VehicleSurfacePolicyScript.ROAD, profile)
		_assert(state.energy_type == StringName(energy_type), energy_type + " uses the shared energy-state contract")
		_assert(state.energy_remaining < state.energy_capacity, energy_type + " consumes energy under propulsion")

	var gentle = VehicleStateScript.new()
	var hard = VehicleStateScript.new()
	var petrol: Dictionary = _default_profile()
	petrol["energy_type"] = "petrol"
	petrol["energy_capacity"] = 50.0
	for _index in range(600):
		_step(gentle, 0.25, 0.0, 0.0, 1.0 / 60.0, VehicleSurfacePolicyScript.ROAD, petrol)
		_step(hard, 1.0, 0.0, 0.7, 1.0 / 60.0, VehicleSurfacePolicyScript.ROAD, petrol)
	var gentle_used: float = gentle.energy_capacity - gentle.energy_remaining
	var hard_used: float = hard.energy_capacity - hard.energy_remaining
	_assert(hard_used > gentle_used, "hard high-demand driving consumes more energy than gentle driving")

	var empty = VehicleStateScript.new()
	empty.energy_type = &"electric"
	empty.energy_capacity = 50.0
	empty.energy_remaining = 0.0
	_step(empty, 1.0, 0.0, 0.0, 1.0 / 60.0, VehicleSurfacePolicyScript.ROAD, {
		"mass_kg": 1550.0,
		"drive_force_n": 4650.0,
		"brake_force_n": 10850.0,
		"tire_grip_coefficient": 1.0,
		"energy_type": "electric",
		"energy_capacity": 50.0,
	})
	_assert(_approx(empty.speed_mps, 0.0), "depleted energy deterministically prevents propulsion")

func _braking_distance(initial_speed_mps: float, surface_overrides: Dictionary) -> float:
	var state = VehicleStateScript.new()
	state.speed_mps = initial_speed_mps
	var surface := {
		"speed_factor": 1.0,
		"acceleration_factor": 1.0,
		"braking_factor": 1.0,
		"steering_factor": 1.0,
		"grip_factor": 1.0,
		"overspeed_deceleration_mps2": 0.0,
	}
	surface.merge(surface_overrides, true)
	for _index in range(1800):
		if absf(state.speed_mps) <= 0.001:
			break
		_step_with_surface(state, 0.0, 1.0, 0.0, 1.0 / 120.0, surface, _default_profile())
	return sqrt(state.x_m * state.x_m + state.z_m * state.z_m)

func _step(
	state,
	throttle: float,
	brake: float,
	steering: float,
	delta_s: float,
	surface_kind: StringName = VehicleSurfacePolicyScript.ROAD,
	profile: Dictionary = {}
) -> void:
	var effective_profile: Dictionary = _default_profile() if profile.is_empty() else profile
	_step_with_surface(state, throttle, brake, steering, delta_s, _surface_policy.modifiers(surface_kind), effective_profile)

func _step_with_surface(
	state,
	throttle: float,
	brake: float,
	steering: float,
	delta_s: float,
	surface_modifiers: Dictionary,
	profile: Dictionary
) -> void:
	_dynamics.call(
		"step",
		state,
		throttle,
		brake,
		steering,
		delta_s,
		4.5,
		36.1,
		3.0,
		7.0,
		5.0,
		32.0,
		surface_modifiers,
		profile
	)

func _default_profile() -> Dictionary:
	return {
		"mass_kg": 1550.0,
		"drive_force_n": 4650.0,
		"brake_force_n": 10850.0,
		"tire_grip_coefficient": 1.0,
		"yaw_response_rps2": 4.0,
		"yaw_grip_ratio": 1.25,
		"energy_type": "none",
		"energy_capacity": 0.0,
		"tire_wear_rate": 0.00008,
	}

func _same_state(a, b) -> bool:
	return (
		_approx(a.x_m, b.x_m)
		and _approx(a.z_m, b.z_m)
		and _approx(a.heading_rad, b.heading_rad)
		and _approx(a.travel_heading_rad, b.travel_heading_rad)
		and _approx(a.speed_mps, b.speed_mps)
		and _approx(a.yaw_rate_rps, b.yaw_rate_rps)
		and _approx(a.energy_remaining, b.energy_remaining)
		and _approx(a.tire_condition, b.tire_condition)
	)

func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.00001

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("vehicle-dynamics test failed: " + message)
	quit(1)
