extends Node

## Composes the real BRUR map, promoted building streaming, atmosphere, camera, and vehicle for #126.
##
## Dependencies:
## - Uses scenes/main.tscn for the production map/camera/sun/world runtime.
## - Uses production BuildingStreamLayer and WorldAtmosphere; owns only experiment controls and status UI.

const PlayerVehicleScene = preload("res://scenes/player_vehicle.tscn")

const CITY_ABSOLUTE := {
	"Malmö": Vector2(1447576.3943775708, 7480180.845685549),
	"Göteborg": Vector2(1333006.3744531337, 7906413.516421634),
	"Stockholm": Vector2(2011387.3513473428, 8251904.234165725),
}
const CITY_SLUG := {"Malmö": "malmo", "Göteborg": "goteborg", "Stockholm": "stockholm"}
const CITY_ORDER := ["Malmö", "Göteborg", "Stockholm", "Malmö"]
const START_ALTITUDE_M := 30000.0
const DIVE_ALTITUDE_M := 1400.0
const RETURN_ALTITUDE_M := 1800.0
const MANUAL_READY_ALTITUDE_M := 5000.0
const PLAYER_HEIGHT_M := 24.8
const CACHE_DIR := "res://.poc_runtime/world_showcase"

@onready var _main: Node = $Main
@onready var _camera_rig: Node = $Main/CameraRig
@onready var _buildings: Node = $Main/BuildingLayer
@onready var _atmosphere: Node = $Main/WorldAtmosphere
@onready var _world_environment: WorldEnvironment = $Main/WorldEnvironment
@onready var _astronomical_sun: DirectionalLight3D = $Main/AstronomicalSun

var _coordinates = null
var _player: Node3D = null
var _current_city := "Malmö"
var _current_world := Vector3.ZERO
var _metrics_accum := 0.0
var _last_metrics: Dictionary = {}
var _status: Label = null
var _dive_button: Button = null
var _manual_button: Button = null
var _map_button: Button = null
var _stress_button: Button = null
var _stress_timer: Timer = null
var _stress_step := -1
var _dive_tween: Tween = null

func _ready() -> void:
	_build_ui()
	call_deferred("_initialize")

func _initialize() -> void:
	_coordinates = _main.call("get_world_coordinates")
	_configure_camera_for_continuous_scale()
	_disable_non_showcase_poi_work()
	_buildings.active_radius_tiles = 0
	_buildings.builds_per_frame = 1
	_buildings.build_budget_ms = 3.5
	_buildings.max_pending_tiles = 4
	_buildings.prefetch_tiles_ahead = 0
	_buildings.appear_altitude_m = 16000.0
	_buildings.hide_altitude_m = 17500.0
	_buildings.full_height_altitude_m = 1800.0
	_buildings.base_height_m = 24.0
	_buildings.call("setup", _coordinates, _camera_rig, CACHE_DIR)
	_atmosphere.call("setup", _world_environment, _astronomical_sun, _camera_rig)
	_jump_to_city("Malmö", START_ALTITUDE_M)
	_spawn_player()
	_update_controls()
	_update_status()

func _disable_non_showcase_poi_work() -> void:
	var poi_layer := _main.get_node_or_null("PoiLayer")
	if poi_layer == null:
		return
	if poi_layer.has_method("set_presentation_enabled"):
		poi_layer.call("set_presentation_enabled", false)
	poi_layer.set_process(false)

func _configure_camera_for_continuous_scale() -> void:
	_camera_rig.overview_pitch_degrees = 84.0
	_camera_rig.overview_fov = 38.0
	_camera_rig.gameplay_pitch_degrees = 36.0
	_camera_rig.gameplay_fov = 56.0
	_camera_rig.gameplay_forward_look = 0.52
	_camera_rig.gameplay_blend_start_altitude_m = START_ALTITUDE_M
	_camera_rig.mode_transition_seconds = 1.0

func _process(delta: float) -> void:
	if _camera_rig == null:
		return
	_update_controls()
	_metrics_accum += delta
	if _metrics_accum < 0.20:
		return
	_metrics_accum = 0.0
	_last_metrics = _buildings.call("consume_perf_metrics") if _buildings != null else {}
	_update_status()

func _spawn_player() -> void:
	_player = PlayerVehicleScene.instantiate() as Node3D
	_player.name = "WorldShowcasePlayer"
	_main.add_child(_player)
	_reset_player_to_current_city()
	_player.visible = false
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_camera_rig.call("set_follow_target", _player)

func _reset_player_to_current_city() -> void:
	if _player == null:
		return
	_player.call("set_world_position", Vector3(_current_world.x, PLAYER_HEIGHT_M, _current_world.z))
	_player.call("set_motion_state", 0.0, -0.55)

func _start_dive() -> void:
	if _camera_rig == null or bool(_camera_rig.call("is_driving_view")):
		return
	_stop_stress()
	if _dive_tween != null and _dive_tween.is_valid():
		_dive_tween.kill()
	var from_altitude := float(_camera_rig.call("get_altitude"))
	if from_altitude <= DIVE_ALTITUDE_M + 50.0:
		_jump_to_city(_current_city, START_ALTITUDE_M)
		from_altitude = START_ALTITUDE_M
	_dive_tween = create_tween()
	_dive_tween.set_trans(Tween.TRANS_CUBIC)
	_dive_tween.set_ease(Tween.EASE_IN_OUT)
	_dive_tween.tween_method(Callable(self, "_set_dive_altitude"), from_altitude, DIVE_ALTITUDE_M, 8.0)

func _set_dive_altitude(altitude_m: float) -> void:
	if _camera_rig != null and not bool(_camera_rig.call("is_driving_view")):
		_camera_rig.call("set_view_altitude", _current_world, altitude_m)

func _enter_manual_drive() -> void:
	if _camera_rig == null or _player == null:
		return
	if float(_camera_rig.call("get_altitude")) > MANUAL_READY_ALTITUDE_M:
		return
	if _dive_tween != null and _dive_tween.is_valid():
		_dive_tween.kill()
	_reset_player_to_current_city()
	_player.visible = true
	_player.process_mode = Node.PROCESS_MODE_INHERIT
	_camera_rig.call("set_follow_target", _player)
	_camera_rig.call("set_drive_mode", true)
	_update_controls()

func _return_to_map() -> void:
	if _camera_rig == null:
		return
	_camera_rig.call("set_drive_mode", false)
	if _player != null:
		_player.process_mode = Node.PROCESS_MODE_DISABLED
		_player.visible = false
	_camera_rig.call("set_view_altitude", _current_world, RETURN_ALTITUDE_M)
	_update_controls()

func _reset_overview() -> void:
	_stop_stress()
	if _dive_tween != null and _dive_tween.is_valid():
		_dive_tween.kill()
	_jump_to_city("Malmö", START_ALTITUDE_M)

func _local_background_path(city: String) -> String:
	return "%s/background_%s.brmap" % [CACHE_DIR, String(CITY_SLUG.get(city, "malmo"))]

func _jump_to_city(city: String, altitude_m: float = 4500.0) -> void:
	if _coordinates == null or _camera_rig == null or not CITY_ABSOLUTE.has(city):
		return
	_current_city = city
	_current_world = _coordinates.absolute_to_world(CITY_ABSOLUTE[city], 0.0)
	_main.call("set_background_source", _local_background_path(city))
	_camera_rig.call("set_drive_mode", false)
	if _player != null:
		_player.process_mode = Node.PROCESS_MODE_DISABLED
		_player.visible = false
		_reset_player_to_current_city()
	_camera_rig.call("set_view_altitude", _current_world, altitude_m)
	_update_controls()

func _start_stress() -> void:
	if _stress_step >= 0:
		_stop_stress()
		return
	if _dive_tween != null and _dive_tween.is_valid():
		_dive_tween.kill()
	_stress_step = 0
	_stress_button.text = "Stop multi-city stress"
	_jump_to_city(CITY_ORDER[_stress_step], 4200.0)
	_stress_timer.start()

func _advance_stress() -> void:
	if _stress_step < 0:
		return
	_stress_step += 1
	if _stress_step >= CITY_ORDER.size():
		_stop_stress()
		return
	_jump_to_city(CITY_ORDER[_stress_step], 4200.0)

func _stop_stress() -> void:
	_stress_step = -1
	if _stress_timer != null:
		_stress_timer.stop()
	if _stress_button != null:
		_stress_button.text = "Stress: Malmö → Göteborg → Stockholm → Malmö"

func _scale_label(altitude: float, driving: bool) -> String:
	if driving:
		return "STREET / DRIVE"
	if altitude > 17000.0:
		return "MAP"
	if altitude > 6000.0:
		return "CITY EMERGING"
	if altitude > 2200.0:
		return "3D CITY"
	return "STREET APPROACH"

func _update_controls() -> void:
	if _manual_button == null or _camera_rig == null:
		return
	var driving := bool(_camera_rig.call("is_driving_view"))
	var altitude := float(_camera_rig.call("get_altitude"))
	_manual_button.disabled = driving or altitude > MANUAL_READY_ALTITUDE_M
	_manual_button.text = "Manual Drive" if altitude <= MANUAL_READY_ALTITUDE_M else "Manual Drive (below 5 km)"
	_map_button.disabled = not driving
	_dive_button.disabled = driving
	_stress_button.disabled = driving

func _update_status() -> void:
	if _status == null or _camera_rig == null:
		return
	var driving := bool(_camera_rig.call("is_driving_view"))
	var altitude := float(_camera_rig.call("get_altitude"))
	var snapshot: Dictionary = _buildings.call("debug_snapshot") if _buildings != null else {}
	var atmosphere: Dictionary = _atmosphere.call("debug_profile") if _atmosphere != null else {}
	var cache_ready := FileAccess.file_exists(CACHE_DIR + "/showcase_manifest.json")
	_status.text = "%s — continuous world showcase\nScale: %s   Altitude: %.0f m   FPS: %d\nBuildings: %d active / %d pending / %d wanted   Records: %d\nBuild max: %.2f ms   Dropped: %d   Fog: %.6f\nCenter tile: %s   Data: %s" % [
		_current_city,
		_scale_label(altitude, driving),
		altitude,
		Engine.get_frames_per_second(),
		int(snapshot.get("active_tiles", 0)),
		int(snapshot.get("pending_tiles", 0)),
		int(snapshot.get("wanted_tiles", 0)),
		int(snapshot.get("active_records", 0)),
		float(_last_metrics.get("building_build_max_ms", 0.0)),
		int(_last_metrics.get("building_dropped_requests", 0)),
		float(atmosphere.get("fog_density", 0.0)),
		String(snapshot.get("last_center_tile", "")),
		"local runtime map + buildings" if cache_ready else "MISSING CACHE",
	]

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 45
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16.0, 16.0)
	panel.custom_minimum_size = Vector2(540.0, 0.0)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	margin.add_child(box)

	var title := Label.new()
	title.text = "BRUR — 30 km → street POC #126"
	box.add_child(title)
	_status = Label.new()
	_status.text = "Preparing existing Sweden showcase data…"
	box.add_child(_status)

	_dive_button = Button.new()
	_dive_button.text = "Cinematic dive: 30 km → 1.4 km"
	_dive_button.pressed.connect(_start_dive)
	box.add_child(_dive_button)

	_manual_button = Button.new()
	_manual_button.text = "Manual Drive (below 5 km)"
	_manual_button.pressed.connect(_enter_manual_drive)
	box.add_child(_manual_button)

	_map_button = Button.new()
	_map_button.text = "Return from drive to map world"
	_map_button.pressed.connect(_return_to_map)
	box.add_child(_map_button)

	_stress_button = Button.new()
	_stress_button.text = "Stress: Malmö → Göteborg → Stockholm → Malmö"
	_stress_button.pressed.connect(_start_stress)
	box.add_child(_stress_button)

	var reset := Button.new()
	reset.text = "Reset Malmö at 30 km"
	reset.pressed.connect(_reset_overview)
	box.add_child(reset)

	var hint := Label.new()
	hint.text = "Mouse wheel/drag/WASD still work in map mode.\nPOI streaming is disabled in this performance POC.\nManual Drive: W/S throttle, A/D steer, Space brake."
	box.add_child(hint)

	_stress_timer = Timer.new()
	_stress_timer.wait_time = 2.5
	_stress_timer.one_shot = false
	_stress_timer.timeout.connect(_advance_stress)
	add_child(_stress_timer)
