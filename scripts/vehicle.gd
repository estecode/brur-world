extends Node3D
class_name Vehicle

## Adapts portable vehicle state/dynamics to a Godot Node3D vehicle instance.
##
## Dependencies:
## - Owns portable vehicle state and delegates deterministic motion/resource limits to VehicleDynamics.
## - Accepts generic controls from exactly one explicit control owner at a time.
## - Receives surface classification explicitly and applies portable VehicleSurfacePolicy modifiers during manual control.
## - Accepts a presentation-only render origin for its VisualRoot without changing logical vehicle state.
## - Exposes emergency light/siren state without depending on police AI decisions.
## - Has no dependency on player input, GPS routing policy, world rendering, traffic AI, police AI, or camera code.

const VehicleStateScript = preload("res://scripts/vehicle_state.gd")
const VehicleDynamicsScript = preload("res://scripts/vehicle_dynamics.gd")
const VehicleSurfacePolicyScript = preload("res://scripts/vehicle_surface_policy.gd")
const STANDARD_CAR_ACCELERATION_MPS2: float = (100.0 / 3.6) / 8.0
const POLICE_V90_D5_ACCELERATION_MPS2: float = (100.0 / 3.6) / 7.5

enum Kind {
	CAR,
	POLICE_CAR,
	FIRE_ENGINE,
	AMBULANCE,
	TRUCK,
	MOTORCYCLE,
	MOPED,
	BICYCLE,
	E_SCOOTER,
}

enum ControlOwner {
	PLAYER,
	GPS,
}

@export var kind: Kind = Kind.CAR
@export var vehicle_id: StringName = &""
@export var vehicle_profile_id: StringName = &"standard_car"
@export var length_m: float = 4.5
@export var width_m: float = 1.8
@export var height_m: float = 1.5
@export var mass_kg: float = 1550.0
@export var max_speed_mps: float = 36.1
@export var acceleration_mps2: float = STANDARD_CAR_ACCELERATION_MPS2
@export var braking_mps2: float = 7.0
@export var drive_force_n: float = STANDARD_CAR_ACCELERATION_MPS2 * 1550.0
@export var brake_force_n: float = 10850.0
@export var max_reverse_speed_mps: float = 5.0
@export var max_steer_degrees: float = 32.0
@export var tire_grip_coefficient: float = 1.0
@export var yaw_response_rps2: float = 4.0
@export var yaw_grip_ratio: float = 1.40
@export_enum("none", "petrol", "diesel", "electric") var energy_type: String = "petrol"
@export var energy_capacity: float = 50.0
@export var active: bool = true

var _emergency_lights_active: bool = false
var _siren_active: bool = false
var _state = VehicleStateScript.new()
var _dynamics = VehicleDynamicsScript.new()
var _surface_policy = VehicleSurfacePolicyScript.new()
var _surface_kind: StringName = VehicleSurfacePolicyScript.ROAD
var _state_initialized: bool = false
var _control_owner: int = ControlOwner.PLAYER
var _throttle_input: float = 0.0
var _brake_input: float = 0.0
var _steering_input: float = 0.0

func _physics_process(delta: float) -> void:
	if not active:
		return
	_ensure_state_from_transform()
	_ensure_resource_state()
	var active_surface: StringName = _surface_kind if _control_owner == ControlOwner.PLAYER else VehicleSurfacePolicyScript.ROAD
	_dynamics.call(
		"step",
		_state,
		_throttle_input,
		_brake_input,
		_steering_input,
		delta,
		length_m,
		max_speed_mps,
		acceleration_mps2,
		braking_mps2,
		max_reverse_speed_mps,
		max_steer_degrees,
		_surface_policy.modifiers(active_surface),
		_physical_profile()
	)
	_apply_state_to_transform()

func configure(new_kind: Kind) -> void:
	kind = new_kind
	_apply_default_profile()
	_reset_resource_state()
	if not is_emergency_vehicle():
		set_emergency_lights_active(false)
		set_siren_active(false)

func set_surface_kind(surface_kind: StringName) -> void:
	_surface_kind = surface_kind

func surface_kind() -> StringName:
	return _surface_kind

func set_control_owner(owner: int) -> void:
	if _control_owner == owner:
		return
	_control_owner = owner
	_clear_inputs_unchecked()

func control_owner() -> int:
	return _control_owner

func set_control_inputs(owner: int, throttle: float, brake: float, steering: float) -> bool:
	if owner != _control_owner:
		return false
	_throttle_input = clampf(throttle, -1.0, 1.0)
	_brake_input = clampf(brake, 0.0, 1.0)
	_steering_input = clampf(steering, -1.0, 1.0)
	return true

func clear_control_inputs(owner: int) -> bool:
	if owner != _control_owner:
		return false
	_clear_inputs_unchecked()
	return true

func set_world_position(new_position: Vector3) -> void:
	_state.x_m = new_position.x
	_state.z_m = new_position.z
	_state_initialized = true
	global_position = Vector3(new_position.x, new_position.y, new_position.z)

func set_render_origin_world(render_origin: Vector3) -> void:
	# Vehicle state and root transform stay in authoritative world coordinates.
	# VisualRoot becomes top-level so its render-local position is not rotated or
	# re-expanded through the large logical parent transform.
	var visual_root := get_node_or_null("VisualRoot") as Node3D
	if visual_root == null:
		return
	visual_root.top_level = true
	var visual_transform := global_transform
	visual_transform.origin = global_position - Vector3(render_origin.x, 0.0, render_origin.z)
	visual_root.global_transform = visual_transform

func set_heading_rad(new_heading_rad: float) -> void:
	_state.heading_rad = wrapf(new_heading_rad, -PI, PI)
	if absf(_state.speed_mps) < 0.05:
		_state.travel_heading_rad = _state.heading_rad
		_state.travel_heading_initialized = true
	_state_initialized = true
	rotation.y = _state.heading_rad

func set_motion_state(new_speed_mps: float, new_heading_rad: float = INF) -> void:
	_ensure_state_from_transform()
	_state.speed_mps = clampf(new_speed_mps, -max_reverse_speed_mps, max_speed_mps)
	if is_finite(new_heading_rad):
		_state.heading_rad = wrapf(new_heading_rad, -PI, PI)
		if absf(_state.speed_mps) < 0.05:
			_state.travel_heading_rad = _state.heading_rad
	_apply_state_to_transform()

func stop() -> void:
	_ensure_state_from_transform()
	_state.speed_mps = 0.0
	_state.yaw_rate_rps = 0.0
	_state.travel_heading_rad = _state.heading_rad
	_state.travel_heading_initialized = true
	_clear_inputs_unchecked()

func speed_mps() -> float:
	return _state.speed_mps

func speed_kmh() -> float:
	return _state.speed_mps * 3.6

func heading_rad() -> float:
	return _state.heading_rad

func energy_remaining() -> float:
	_ensure_resource_state()
	return _state.energy_remaining

func tire_condition() -> float:
	return _state.tire_condition

func profile_id() -> StringName:
	return vehicle_profile_id

func state_snapshot():
	_ensure_state_from_transform()
	_ensure_resource_state()
	return _state.duplicate_state()

func is_emergency_vehicle() -> bool:
	return kind in [Kind.POLICE_CAR, Kind.FIRE_ENGINE, Kind.AMBULANCE]

func set_emergency_lights_active(enabled: bool) -> bool:
	if enabled and kind != Kind.POLICE_CAR:
		return false
	_emergency_lights_active = enabled
	var visual := get_node_or_null("VisualRoot/PoliceEmergencyVisual")
	if visual != null and visual.has_method("set_emergency_lights_active"):
		visual.call("set_emergency_lights_active", enabled)
	return true

func emergency_lights_active() -> bool:
	return _emergency_lights_active

func set_siren_active(enabled: bool) -> bool:
	if enabled and not is_emergency_vehicle():
		return false
	_siren_active = enabled
	return true

func siren_active() -> bool:
	return _siren_active

func _ensure_state_from_transform() -> void:
	if _state_initialized:
		return
	_state.x_m = global_position.x
	_state.z_m = global_position.z
	_state.heading_rad = rotation.y
	_state.travel_heading_rad = rotation.y
	_state.travel_heading_initialized = true
	_state_initialized = true

func _ensure_resource_state() -> void:
	if _state.energy_type == &"":
		_state.energy_type = StringName(energy_type)
	if _state.energy_capacity <= 0.0 and energy_capacity > 0.0:
		_state.energy_capacity = energy_capacity
		_state.energy_remaining = energy_capacity

func _apply_state_to_transform() -> void:
	global_position.x = _state.x_m
	global_position.z = _state.z_m
	rotation.y = _state.heading_rad

func _clear_inputs_unchecked() -> void:
	_throttle_input = 0.0
	_brake_input = 0.0
	_steering_input = 0.0

func _physical_profile() -> Dictionary:
	return {
		"mass_kg": mass_kg,
		"drive_force_n": drive_force_n,
		"brake_force_n": brake_force_n,
		"tire_grip_coefficient": tire_grip_coefficient,
		"yaw_response_rps2": yaw_response_rps2,
		"yaw_grip_ratio": yaw_grip_ratio,
		"energy_type": energy_type,
		"energy_capacity": energy_capacity,
		"tire_wear_rate": 0.00008,
	}

func _reset_resource_state() -> void:
	_state.energy_type = StringName(energy_type)
	_state.energy_capacity = maxf(0.0, energy_capacity)
	_state.energy_remaining = _state.energy_capacity
	_state.tire_condition = 1.0

func _apply_default_profile() -> void:
	match kind:
		Kind.CAR:
			_set_profile(&"standard_car", 4.5, 1.8, 1.5, 1550.0, 36.1, STANDARD_CAR_ACCELERATION_MPS2, 7.0, 1.00, "petrol", 50.0)
		Kind.POLICE_CAR:
			# Volvo V90 Cross Country D5 AWD: 4939 x 1879 x 1543 mm, 0-100 in 7.5 s,
			# 230 km/h and diesel. 1950 kg is a documented gameplay approximation for
			# police equipment above the civilian 1834-1882 kg manufacturer range.
			_set_profile(&"se_police_volvo_v90_cc_d5_2017", 4.939, 1.879, 1.543, 1950.0, 230.0 / 3.6, POLICE_V90_D5_ACCELERATION_MPS2, 8.0, 1.08, "diesel", 60.0)
		Kind.FIRE_ENGINE:
			_set_profile(&"fire_engine", 8.5, 2.5, 3.2, 12000.0, 27.8, 1.5, 6.0, 0.82, "diesel", 300.0)
		Kind.AMBULANCE:
			_set_profile(&"ambulance", 6.0, 2.1, 2.7, 3500.0, 44.4, 2.8, 7.5, 0.90, "diesel", 90.0)
		Kind.TRUCK:
			_set_profile(&"truck", 12.0, 2.5, 3.8, 18000.0, 25.0, 1.0, 5.0, 0.75, "diesel", 400.0)
		Kind.MOTORCYCLE:
			_set_profile(&"motorcycle", 2.2, 0.8, 1.3, 220.0, 50.0, 5.0, 9.0, 1.05, "petrol", 18.0)
		Kind.MOPED:
			_set_profile(&"moped", 1.9, 0.7, 1.2, 120.0, 12.5, 2.5, 6.0, 0.85, "petrol", 6.0)
		Kind.BICYCLE:
			_set_profile(&"bicycle", 1.8, 0.65, 1.2, 100.0, 12.0, 1.5, 4.0, 0.90, "none", 0.0)
		Kind.E_SCOOTER:
			_set_profile(&"e_scooter", 1.2, 0.55, 1.2, 25.0, 7.0, 2.0, 4.0, 0.75, "electric", 0.50)

func _set_profile(
	new_profile_id: StringName,
	new_length_m: float,
	new_width_m: float,
	new_height_m: float,
	new_mass_kg: float,
	new_max_speed_mps: float,
	new_acceleration_mps2: float,
	new_braking_mps2: float,
	new_tire_grip_coefficient: float,
	new_energy_type: String,
	new_energy_capacity: float
) -> void:
	vehicle_profile_id = new_profile_id
	length_m = new_length_m
	width_m = new_width_m
	height_m = new_height_m
	mass_kg = new_mass_kg
	max_speed_mps = new_max_speed_mps
	acceleration_mps2 = new_acceleration_mps2
	braking_mps2 = new_braking_mps2
	drive_force_n = new_acceleration_mps2 * new_mass_kg
	brake_force_n = new_braking_mps2 * new_mass_kg
	tire_grip_coefficient = new_tire_grip_coefficient
	energy_type = new_energy_type
	energy_capacity = new_energy_capacity
