extends RefCounted

## Owns deterministic camera altitude state and display formatting in real-world metres.
##
## Dependencies:
## - No SceneTree, rendering, world-coordinate, cloud, or weather dependencies.

var min_altitude_m: float
var max_altitude_m: float
var altitude_m: float

func _init(minimum_m: float, maximum_m: float, initial_m: float) -> void:
	assert(minimum_m > 0.0)
	assert(maximum_m >= minimum_m)
	min_altitude_m = minimum_m
	max_altitude_m = maximum_m
	altitude_m = clampf(initial_m, min_altitude_m, max_altitude_m)

func set_altitude(new_altitude_m: float) -> float:
	altitude_m = clampf(new_altitude_m, min_altitude_m, max_altitude_m)
	return altitude_m

func zoom_by(factor: float) -> float:
	if factor <= 0.0:
		return altitude_m
	return set_altitude(altitude_m * factor)

func get_altitude() -> float:
	return altitude_m

func format_readout() -> String:
	return format_altitude(altitude_m)

static func format_altitude(value_m: float) -> String:
	var clamped_m: float = maxf(0.0, value_m)
	if clamped_m < 1000.0:
		return "Camera: %d m" % roundi(clamped_m)
	return "Camera: %.1f km" % (clamped_m / 1000.0)
