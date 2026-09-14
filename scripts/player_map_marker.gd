extends Node3D
class_name PlayerMapMarker

## Presents the shared player car at a readable top-down scale in Map mode.
##
## Dependencies:
## - Reuses PlayerCarVisual geometry so Map and Drive show the same car presentation.
## - Receives camera distance and vehicle heading explicitly from GpsRouteLayer.
## - Owns presentation scaling only; it never changes vehicle simulation dimensions or coordinates.

const PlayerCarVisualScript = preload("res://scripts/player_car_visual.gd")
const PHYSICAL_SCALE_DISTANCE_M := 800.0
const FAR_SCALE_EXPONENT := 1.30
const MAX_VISUAL_SCALE := 8192.0

var _car_visual: Node3D

func _ready() -> void:
	if _car_visual == null:
		_car_visual = PlayerCarVisualScript.new() as Node3D
		_car_visual.name = "CarVisual"
		add_child(_car_visual)
		_car_visual.call("set_overlay_mode", true)

func set_view_state(camera_distance_m: float, driving_view: bool, vehicle_heading_rad: float) -> void:
	visible = not driving_view
	rotation.y = vehicle_heading_rad
	var visual_scale := scale_for_distance(camera_distance_m)
	scale = Vector3.ONE * visual_scale

static func scale_for_distance(camera_distance_m: float) -> float:
	if camera_distance_m <= PHYSICAL_SCALE_DISTANCE_M:
		return 1.0
	var ratio := camera_distance_m / PHYSICAL_SCALE_DISTANCE_M
	return clampf(pow(ratio, FAR_SCALE_EXPONENT), 1.0, MAX_VISUAL_SCALE)

static func physical_size_m() -> Vector2:
	return PlayerCarVisualScript.physical_size_m()
