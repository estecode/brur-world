extends VehicleController
class_name PlayerVehicleController

## Reads player keyboard input and translates it into player-owned Vehicle controls.
##
## Dependencies:
## - W/S accelerate/reverse, A/D steer, Space brakes.
## - Emits manual_input_detected so composition can disengage GPS follow before applying player intent.
## - Owns no vehicle physics or routing logic.

signal manual_input_detected

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
	if not is_zero_approx(throttle) or not is_zero_approx(steer) or brake > 0.0:
		manual_input_detected.emit()
	vehicle.set_control_inputs(Vehicle.ControlOwner.PLAYER, throttle, brake, steer)

func _clear_owned_controls() -> void:
	if vehicle != null:
		vehicle.clear_control_inputs(Vehicle.ControlOwner.PLAYER)
