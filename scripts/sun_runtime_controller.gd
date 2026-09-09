extends Node
class_name SunRuntimeController

## Drives the game's astronomical sun from the authoritative WorldClock and exposes the current solar state.
## Dependencies: sun_light_adapter.gd plus explicitly configured WorldClockRuntime, DirectionalLight3D, and Button scene nodes.

signal solar_state_changed(solar_state: Dictionary)

const SunLightAdapterScript = preload("res://scripts/sun_light_adapter.gd")

@export_node_path("Node") var world_clock_path: NodePath
@export_node_path("DirectionalLight3D") var astronomical_light_path: NodePath
@export_node_path("DirectionalLight3D") var legacy_light_path: NodePath
@export_node_path("BaseButton") var legacy_toggle_path: NodePath
@export var latitude_deg := 59.3293
@export var longitude_deg := 18.0686
@export_range(0.1, 60.0, 0.1) var update_interval_seconds := 1.0

var _adapter = SunLightAdapterScript.new()
var _world_clock_runtime: Node
var _astronomical_light: DirectionalLight3D
var _legacy_light: DirectionalLight3D
var _legacy_toggle: BaseButton
var _time_source: Callable
var _time_override: Dictionary = {}
var _elapsed_seconds := 0.0
var _last_solar_state: Dictionary = {"valid": false}

func _ready() -> void:
	_world_clock_runtime = get_node_or_null(world_clock_path)
	_astronomical_light = get_node_or_null(astronomical_light_path) as DirectionalLight3D
	_legacy_light = get_node_or_null(legacy_light_path) as DirectionalLight3D
	_legacy_toggle = get_node_or_null(legacy_toggle_path) as BaseButton
	if _astronomical_light == null:
		push_error("SunRuntimeController requires an astronomical DirectionalLight3D")
		set_process(false)
		return
	if not _time_source.is_valid() and (_world_clock_runtime == null or not _world_clock_runtime.has_method("get_utc_snapshot")):
		push_error("SunRuntimeController requires WorldClockRuntime or an explicit time source")
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

func set_time_override(snapshot: Dictionary) -> void:
	_time_override = snapshot.duplicate(true)
	refresh_now()

func clear_time_override() -> void:
	_time_override.clear()
	refresh_now()

func time_override_enabled() -> bool:
	return not _time_override.is_empty()

func set_location(latitude: float, longitude: float) -> void:
	latitude_deg = latitude
	longitude_deg = longitude
	refresh_now()

func set_legacy_light_enabled(enabled: bool) -> void:
	if _legacy_light != null:
		_legacy_light.visible = enabled

func legacy_light_enabled() -> bool:
	return _legacy_light != null and _legacy_light.visible

func get_last_solar_state() -> Dictionary:
	return _last_solar_state.duplicate(true)

func refresh_now() -> Dictionary:
	if _astronomical_light == null:
		return {"valid": false}
	var snapshot := _read_time_snapshot()
	if not bool(snapshot.get("valid", true)):
		return {"valid": false}
	_last_solar_state = _adapter.apply_time_snapshot(snapshot, latitude_deg, longitude_deg)
	if bool(_last_solar_state.get("valid", false)):
		solar_state_changed.emit(_last_solar_state.duplicate(true))
	return _last_solar_state.duplicate(true)

func _read_time_snapshot() -> Dictionary:
	if not _time_override.is_empty():
		return _time_override
	if _time_source.is_valid():
		var supplied: Variant = _time_source.call()
		if supplied is Dictionary:
			return supplied as Dictionary
	if _world_clock_runtime != null and _world_clock_runtime.has_method("get_utc_snapshot"):
		var supplied: Variant = _world_clock_runtime.call("get_utc_snapshot")
		if supplied is Dictionary:
			return supplied as Dictionary
	return {"valid": false}
