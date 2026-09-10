extends Node
class_name WorldAtmosphere

## Adds altitude-driven haze/depth presentation without owning world time or sun position.
##
## Dependencies:
## - Composition supplies the existing WorldEnvironment, astronomical sun, and camera rig.
## - Reads camera altitude only; does not own coordinates, world data, lighting time, or routing.

@export var haze_start_altitude_m: float = 30000.0
@export var full_haze_altitude_m: float = 3500.0
@export var shadow_enable_altitude_m: float = 18000.0
@export var enable_dynamic_shadows: bool = false
@export var max_fog_density: float = 0.000085
@export var near_ambient_energy: float = 0.82
@export var far_ambient_energy: float = 1.05

var _world_environment: WorldEnvironment = null
var _astronomical_sun: DirectionalLight3D = null
var _camera_rig: Node = null
var _environment: Environment = null

static func profile_for_altitude(
	altitude_m: float,
	haze_start_m: float = 30000.0,
	full_haze_m: float = 3500.0,
	max_density: float = 0.000085
) -> Dictionary:
	var raw := 0.0
	if altitude_m < haze_start_m:
		raw = 1.0 - inverse_lerp(full_haze_m, haze_start_m, altitude_m)
	var blend := clampf(raw, 0.0, 1.0)
	var eased := blend * blend * (3.0 - 2.0 * blend)
	return {
		"blend": eased,
		"fog_density": max_density * eased,
		"fog_sun_scatter": lerpf(0.0, 0.12, eased),
		"background_color": Color(0.34, 0.56, 0.76).lerp(Color(0.48, 0.60, 0.68), eased * 0.55),
	}

func setup(world_environment: WorldEnvironment, astronomical_sun: DirectionalLight3D, camera_rig: Node) -> void:
	assert(world_environment != null, "WorldAtmosphere requires WorldEnvironment")
	assert(camera_rig != null, "WorldAtmosphere requires a camera rig")
	_world_environment = world_environment
	_astronomical_sun = astronomical_sun
	_camera_rig = camera_rig
	_environment = _world_environment.environment
	if _environment == null:
		_environment = Environment.new()
		_world_environment.environment = _environment
	_environment.fog_enabled = true
	_environment.fog_light_color = Color(0.76, 0.82, 0.88)
	_environment.fog_light_energy = 0.72
	_environment.fog_height = 0.0
	_environment.fog_height_density = 0.0
	_apply(float(_camera_rig.call("get_altitude")))

func _process(_delta: float) -> void:
	if _environment == null or _camera_rig == null:
		return
	_apply(float(_camera_rig.call("get_altitude")))

func _apply(altitude_m: float) -> void:
	var profile := profile_for_altitude(altitude_m, haze_start_altitude_m, full_haze_altitude_m, max_fog_density)
	var blend := float(profile["blend"])
	_environment.fog_density = float(profile["fog_density"])
	_environment.fog_sun_scatter = float(profile["fog_sun_scatter"])
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = profile["background_color"]
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.78, 0.86, 0.95).lerp(Color(0.70, 0.76, 0.82), blend * 0.45)
	_environment.ambient_light_energy = lerpf(far_ambient_energy, near_ambient_energy, blend)
	if _astronomical_sun != null:
		_astronomical_sun.shadow_enabled = enable_dynamic_shadows and altitude_m <= shadow_enable_altitude_m

func debug_profile() -> Dictionary:
	if _camera_rig == null:
		return {}
	return profile_for_altitude(float(_camera_rig.call("get_altitude")), haze_start_altitude_m, full_haze_altitude_m, max_fog_density)
