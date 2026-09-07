extends VehicleController
class_name PlayerVehicleController

## Reads player keyboard input and translates it into generic Vehicle controls.
##
## Dependencies:
## - W/S accelerate and reverse/brake, A/D steer, Space applies the brake.
## - Owns no vehicle physics; it only commands Vehicle.
## - Input actions can replace these direct keys later without changing Vehicle.

func _apply_controls() -> void:
	var throttle: float = 0.0
	if Input.is_physical_key_pressed(KEY_W):
		throttle += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		throttle -= 1.0

	var steer: float = 0.0
	if Input.is_physical_key_pressed(KEY_D):
		steer += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		steer -= 1.0

	var brake: float = 1.0 if Input.is_physical_key_pressed(KEY_SPACE) else 0.0
	vehicle.set_control_inputs(throttle, brake, steer)
