extends Node3D
class_name Vehicle

## Shared runtime object for anything that moves as a road vehicle.
##
## Dependencies:
## - Has no dependency on player input, traffic AI, police AI, routing, or rendering.
## - Controllers may drive the public motion state while this object owns common vehicle data.
## - The same object is intended for cars, emergency vehicles, trucks, motorcycles,
##   mopeds, bicycles, e-scooters and future vehicle types.

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

@export var kind: Kind = Kind.CAR
@export var vehicle_id: StringName = &""

# Physical footprint in real metres. These are gameplay/simulation values,
# independent from Mercator/render coordinates.
@export var length_m: float = 4.5
@export var width_m: float = 1.8
@export var height_m: float = 1.5

# Motion limits in real SI units.
@export var max_speed_mps: float = 36.1 # ~130 km/h
@export var acceleration_mps2: float = 3.0
@export var braking_mps2: float = 7.0
@export var max_reverse_speed_mps: float = 5.0

# Shared dynamic state. A player controller, traffic controller or emergency
# controller may update these without changing the base vehicle object.
var speed_mps: float = 0.0
var target_speed_mps: float = 0.0
var steering: float = 0.0
var active: bool = true
var emergency_lights_active: bool = false

func configure(new_kind: Kind) -> void:
	kind = new_kind
	_apply_default_profile()

func set_target_speed(new_target_mps: float) -> void:
	target_speed_mps = clampf(new_target_mps, -max_reverse_speed_mps, max_speed_mps)

func set_motion_state(new_speed_mps: float, new_steering: float = 0.0) -> void:
	speed_mps = clampf(new_speed_mps, -max_reverse_speed_mps, max_speed_mps)
	steering = clampf(new_steering, -1.0, 1.0)

func stop() -> void:
	target_speed_mps = 0.0
	speed_mps = 0.0
	steering = 0.0

func is_emergency_vehicle() -> bool:
	return kind in [Kind.POLICE_CAR, Kind.FIRE_ENGINE, Kind.AMBULANCE]

func speed_kmh() -> float:
	return speed_mps * 3.6

func _apply_default_profile() -> void:
	# Deliberately simple first-pass defaults. Later vehicle definitions can move
	# to Resources/data files without changing controllers that talk to Vehicle.
	match kind:
		Kind.CAR:
			_set_profile(4.5, 1.8, 1.5, 36.1, 3.0, 7.0)
		Kind.POLICE_CAR:
			_set_profile(4.8, 1.9, 1.5, 55.6, 4.5, 9.0)
		Kind.FIRE_ENGINE:
			_set_profile(8.5, 2.5, 3.2, 27.8, 1.5, 6.0)
		Kind.AMBULANCE:
			_set_profile(6.0, 2.1, 2.7, 44.4, 2.8, 7.5)
		Kind.TRUCK:
			_set_profile(12.0, 2.5, 3.8, 25.0, 1.0, 5.0)
		Kind.MOTORCYCLE:
			_set_profile(2.2, 0.8, 1.3, 50.0, 5.0, 9.0)
		Kind.MOPED:
			_set_profile(1.9, 0.7, 1.2, 12.5, 2.5, 6.0)
		Kind.BICYCLE:
			_set_profile(1.8, 0.65, 1.2, 12.0, 1.5, 4.0)
		Kind.E_SCOOTER:
			_set_profile(1.2, 0.55, 1.2, 7.0, 2.0, 4.0)

func _set_profile(
	new_length_m: float,
	new_width_m: float,
	new_height_m: float,
	new_max_speed_mps: float,
	new_acceleration_mps2: float,
	new_braking_mps2: float
) -> void:
	length_m = new_length_m
	width_m = new_width_m
	height_m = new_height_m
	max_speed_mps = new_max_speed_mps
	acceleration_mps2 = new_acceleration_mps2
	braking_mps2 = new_braking_mps2
