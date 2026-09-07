extends VehicleController
class_name PlayerVehicleController

## Reads player input and translates it into generic Vehicle controls.
##
## Dependencies:
## - Uses the input actions vehicle_accelerate, vehicle_brake, vehicle_left,
##   vehicle_right and vehicle_handbrake from project.godot.
## - Owns no vehicle physics; it only commands Vehicle.

func _apply_controls() -> void:
	var throttle: float = Input.get_action_strength("vehicle_accelerate") - Input.get_action_strength("vehicle_brake")
	var steer: float = Input.get_action_strength("vehicle_right") - Input.get_action_strength("vehicle_left")
	var brake: float = Input.get_action_strength("vehicle_handbrake")
	vehicle.set_control_inputs(throttle, brake, steer)
