extends Node
class_name DayNightEnvironmentAdapter

## Darkens the shared world environment as the authoritative astronomical sun goes below the horizon.
##
## Dependencies:
## - Reads solar state from an explicitly configured SunRuntimeController.
## - Writes presentation values only to an explicitly configured WorldEnvironment.

@export_node_path("Node") var sun_controller_path: NodePath
@export_node_path("WorldEnvironment") var world_environment_path: NodePath

const DAY_BACKGROUND := Color(0.34, 0.56, 0.76)
const NIGHT_BACKGROUND := Color(0.045, 0.075, 0.12)
const DAY_AMBIENT := Color(0.78, 0.86, 0.95)
const NIGHT_AMBIENT := Color(0.13, 0.17, 0.24)
const DAY_AMBIENT_ENERGY := 1.05
const NIGHT_AMBIENT_ENERGY := 0.23

var _sun_controller: Node
var _world_environment: WorldEnvironment
var _last_solar_state: Dictionary = {"valid": false}
var _environment_applied := false

func _ready() -> void:
	_sun_controller = get_node_or_null(sun_controller_path)
	_world_environment = get_node_or_null(world_environment_path) as WorldEnvironment
	if _sun_controller != null and _sun_controller.has_signal("solar_state_changed"):
		_sun_controller.connect("solar_state_changed", _on_solar_state_changed)
	refresh_now()

func _process(_delta: float) -> void:
	if _environment_applied:
		return
	if _world_environment != null and _world_environment.environment != null:
		refresh_now()

func refresh_now() -> void:
	if _sun_controller != null and _sun_controller.has_method("get_last_solar_state"):
		var state: Variant = _sun_controller.call("get_last_solar_state")
		if state is Dictionary:
			apply_solar_state(state as Dictionary)

func apply_solar_state(solar_state: Dictionary) -> void:
	if not bool(solar_state.get("valid", false)):
		return
	_last_solar_state = solar_state.duplicate(true)
	_apply_environment()

func get_environment_stats() -> Dictionary:
	return {
		"night_factor": _night_factor(float(_last_solar_state.get("elevation_deg", 90.0))) if bool(_last_solar_state.get("valid", false)) else 0.0,
		"applied": _environment_applied,
	}

func _apply_environment() -> void:
	if _world_environment == null or _world_environment.environment == null:
		_environment_applied = false
		return
	var night_factor := _night_factor(float(_last_solar_state.get("elevation_deg", 90.0)))
	var environment := _world_environment.environment
	environment.background_color = DAY_BACKGROUND.lerp(NIGHT_BACKGROUND, night_factor)
	environment.ambient_light_color = DAY_AMBIENT.lerp(NIGHT_AMBIENT, night_factor)
	environment.ambient_light_energy = lerpf(DAY_AMBIENT_ENERGY, NIGHT_AMBIENT_ENERGY, night_factor)
	_environment_applied = true

func _night_factor(elevation_deg: float) -> float:
	var t := clampf((2.0 - elevation_deg) / 10.0, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _on_solar_state_changed(solar_state: Dictionary) -> void:
	_environment_applied = false
	apply_solar_state(solar_state)
