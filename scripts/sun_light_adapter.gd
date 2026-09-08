extends Node
class_name SunLightAdapter

## Applies production solar-position results to a Godot DirectionalLight3D.
## Dependencies: sun_position_model.gd and one explicitly provided DirectionalLight3D; does not own time, world coordinates, or gameplay state.

const SunPositionModelScript = preload("res://scripts/sun_position_model.gd")

@export var maximum_light_energy := 2.15

var _model = SunPositionModelScript.new()
var _light: DirectionalLight3D

func setup(light: DirectionalLight3D) -> void:
	_light = light

func apply_time_snapshot(time_snapshot: Dictionary, latitude_deg: float, longitude_deg: float) -> Dictionary:
	var solar_state: Dictionary = _model.calculate(time_snapshot, latitude_deg, longitude_deg)
	if not bool(solar_state.get("valid", false)):
		return solar_state
	apply_solar_state(solar_state)
	return solar_state

func apply_solar_state(solar_state: Dictionary) -> bool:
	if _light == null or not bool(solar_state.get("valid", false)):
		return false
	var azimuth_deg := float(solar_state["azimuth_deg"])
	var elevation_deg := float(solar_state["elevation_deg"])
	var sun_direction := _sun_direction(azimuth_deg, elevation_deg)
	var ray_direction := -sun_direction
	var up := Vector3.UP
	if absf(ray_direction.dot(up)) > 0.999:
		up = Vector3.FORWARD
	var light_transform := _light.global_transform
	light_transform.basis = Basis.looking_at(ray_direction, up)
	_light.global_transform = light_transform
	var daylight_factor := clampf(sin(deg_to_rad(maxf(elevation_deg, 0.0))), 0.0, 1.0)
	_light.light_energy = maximum_light_energy * daylight_factor
	_light.visible = elevation_deg > 0.0
	return true

func _sun_direction(azimuth_deg: float, elevation_deg: float) -> Vector3:
	var azimuth_rad := deg_to_rad(azimuth_deg)
	var elevation_rad := deg_to_rad(elevation_deg)
	var horizontal := cos(elevation_rad)
	# brur-world uses +X east and -Z north, matching world_coordinates.gd.
	return Vector3(
		sin(azimuth_rad) * horizontal,
		sin(elevation_rad),
		-cos(azimuth_rad) * horizontal
	).normalized()
