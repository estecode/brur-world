class_name VehicleSurfacePolicy
extends RefCounted

## Defines deterministic vehicle performance modifiers for road and off-road surfaces.
##
## Dependencies:
## - Pure vehicle-domain policy with no SceneTree, rendering, world-data, or input dependency.
## - VehicleDynamics consumes the returned scalar modifiers.

const ROAD: StringName = &"road"
const OFF_ROAD: StringName = &"off_road"

func modifiers(surface_kind: StringName) -> Dictionary:
	if surface_kind == OFF_ROAD:
		return {
			"speed_factor": 0.45,
			"acceleration_factor": 0.55,
			"braking_factor": 0.60,
			"steering_factor": 0.65,
			"overspeed_deceleration_mps2": 2.0,
		}
	return {
		"speed_factor": 1.0,
		"acceleration_factor": 1.0,
		"braking_factor": 1.0,
		"steering_factor": 1.0,
		"overspeed_deceleration_mps2": 0.0,
	}
