extends Node
class_name SunRuntimeController

## Drives the game's astronomical sun from an explicit or temporary system-time source and controls the optional legacy light.
## Dependencies: sun_light_adapter.gd plus explicitly configured DirectionalLight3D/Button scene nodes; WorldClock can replace the fallback time source later.

const SunLightAdapterScript = preload("res://scripts/sun_light_adapter.gd")

@export_node_path("DirectionalLight3D") var astronomical_light_path: NodePath
@export_node_path("DirectionalLight3D") var legacy_light_path: NodePath
@export_node_path("BaseButton") var legacy_toggle_path: NodePath
@export var latitude_deg := 59.3293
@export var longitude_deg := 18.0686
@export_range(0.1, 60.0, 0.1) var update_interval_seconds := 1.0

var _adapter = SunLightAdapterScript.new()
var _astronomical_light: DirectionalLight3D
var _legacy_light: DirectionalLight3D
var _legacy_toggle: BaseButton
var _time_source: Callable
var _elapsed_seconds := 0.0

func _ready() -> void:
	_astronomical_light = get_node_or_null(astronomical_light_path) as DirectionalLight3D
	_legacy_light = get_node_or_null(legacy_light_path) as DirectionalLight3D
	_legacy_toggle = get_node_or_null(legacy_toggle_path) as BaseButton
	if _astronomical_light == null:
		push_error("SunRuntimeController requires an astronomical DirectionalLight3D")
		set_process(false)
		return
	_adapter.setup(_astronomical_light)
	set_legacy_light_enabled(false)
	if _legacy_toggle != null:
		_legacy_toggle.button_pressed = false
		_legacy_toggle.toggled.connect(set_legacy_light_enabled)
	refresh_now()

func _process(delta: float) -> void:
	_elapsed_seconds += delta
	if _elapsed_seconds < update_interval_seconds:
		return
	_elapsed_seconds = 0.0
	refresh_now()

func set_time_source(source: Callable) -> void:
	_time_source = source

func set_location(latitude: float, longitude: float) -> void:
	latitude_deg = latitude
	longitude_deg = longitude
	refresh_now()

func set_legacy_light_enabled(enabled: bool) -> void:
	if _legacy_light != null:
		_legacy_light.visible = enabled

func legacy_light_enabled() -> bool:
	return _legacy_light != null and _legacy_light.visible

func refresh_now() -> Dictionary:
	if _astronomical_light == null:
		return {"valid": false}
	return _adapter.apply_time_snapshot(_read_time_snapshot(), latitude_deg, longitude_deg)

func _read_time_snapshot() -> Dictionary:
	if _time_source.is_valid():
		var supplied: Variant = _time_source.call()
		if supplied is Dictionary:
			return supplied as Dictionary
	var local_time: Dictionary = Time.get_datetime_dict_from_system()
	var time_zone: Dictionary = Time.get_time_zone_from_system()
	return {
		"year": int(local_time.get("year", 0)),
		"month": int(local_time.get("month", 0)),
		"day": int(local_time.get("day", 0)),
		"hour": int(local_time.get("hour", 0)),
		"minute": int(local_time.get("minute", 0)),
		"second": int(local_time.get("second", 0)),
		"utc_offset_hours": float(time_zone.get("bias", 0)) / 60.0,
	}
