extends SceneTree

## Deterministic contract tests for portable vehicle state/dynamics.
## Dependencies: scripts/vehicle_state.gd and scripts/vehicle_dynamics.gd only.

const VehicleStateScript = preload("res://scripts/vehicle_state.gd")
const VehicleDynamicsScript = preload("res://scripts/vehicle_dynamics.gd")

var _dynamics = VehicleDynamicsScript.new()

func _init() -> void:
	var forward = VehicleStateScript.new()
	_step(forward, 1.0, 0.0, 0.0, 1.0)
	_assert(_approx(forward.speed_mps, 3.0), "full throttle accelerates by configured m/s²")
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
	_assert(absf(steering.heading_rad) > 0.01, "steering changes heading while moving")

	var limited = VehicleStateScript.new()
	limited.speed_mps = 35.5
	_step(limited, 1.0, 0.0, 5.0, 1.0)
	_assert(_approx(limited.speed_mps, 36.1), "forward speed limit is enforced")

	var first = VehicleStateScript.new()
	var second = VehicleStateScript.new()
	for _index in range(120):
		_step(first, 0.72, 0.0, -0.35, 1.0 / 60.0)
		_step(second, 0.72, 0.0, -0.35, 1.0 / 60.0)
	_assert(_approx(first.x_m, second.x_m) and _approx(first.z_m, second.z_m), "repeated simulation preserves position deterministically")
	_assert(_approx(first.heading_rad, second.heading_rad) and _approx(first.speed_mps, second.speed_mps), "repeated simulation preserves heading/speed deterministically")

	print("godot vehicle-dynamics tests: OK")
	quit(0)

func _step(state, throttle: float, brake: float, steering: float, delta_s: float) -> void:
	_dynamics.call("step", state, throttle, brake, steering, delta_s, 4.5, 36.1, 3.0, 7.0, 5.0, 32.0)

func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.00001

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("vehicle-dynamics test failed: " + message)
	quit(1)
