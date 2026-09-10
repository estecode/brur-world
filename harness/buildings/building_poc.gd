extends Node

## Composes production world/building/camera/vehicle modules for the #122 streaming POC harness.
##
## Dependencies:
## - Uses the parent production world renderer for existing BRUR map data and shared coordinates.
## - Uses production BuildingStreamLayer, CameraRig, and player_vehicle scene; owns only harness controls/status.

const PlayerVehicleScene = preload("res://scenes/player_vehicle.tscn")
const CITY_ABSOLUTE := {
	"Malmö": Vector2(1447576.3943775708, 7480180.845685549),
	"Göteborg": Vector2(1333006.3744531337, 7906413.516421634),
	"Stockholm": Vector2(2011387.3513473428, 8251904.234165725),
}
const CITY_ORDER := ["Malmö", "Göteborg", "Stockholm", "Malmö"]
const START_ALTITUDE_M: float = 180000.0
const MANUAL_READY_ALTITUDE_M: float = 5000.0
const PLAYER_HEIGHT_M: float = 24.8

var _main: Node = null
var _camera_rig: Node = null
var _buildings: Node = null
var _coordinates = null
var _player: Node3D = null
var _manual_button: Button = null
var _map_button: Button = null
var _stress_button: Button = null
var _status: Label = null
var _metrics_accum: float = 0.0
var _current_city := "Malmö"
var _current_world := Vector3.ZERO
var _stress_step := -1
var _stress_timer: Timer = null
var _last_metrics: Dictionary = {}

func _ready() -> void:
	_build_ui()
	call_deferred("_initialize")

func _initialize() -> void:
	_main = get_parent()
	_camera_rig = _main.get_node("CameraRig")
	_buildings = _main.get_node("BuildingLayer")
	_coordinates = _main.call("get_world_coordinates")
	_buildings.call("setup", _coordinates, _camera_rig)
	_jump_to_city("Malmö", START_ALTITUDE_M)
	_spawn_player()
	_update_controls()

func _process(delta: float) -> void:
	if _camera_rig == null:
		return
	_update_controls()
	_metrics_accum += delta
	if _metrics_accum < 0.25:
		return
	_metrics_accum = 0.0
	_last_metrics = _buildings.call("consume_perf_metrics") if _buildings != null else {}
	_update_status()

func _spawn_player() -> void:
	_player = PlayerVehicleScene.instantiate() as Node3D
	_player.name = "PocPlayerVehicle"
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

func _enter_manual_drive() -> void:
	if _camera_rig == null or _player == null:
		return
	if float(_camera_rig.call("get_altitude")) > MANUAL_READY_ALTITUDE_M:
		return
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
	_camera_rig.call("set_view_altitude", _current_world, 4500.0)
	_update_controls()

func _reset_overview() -> void:
	_stop_stress()
	_jump_to_city("Malmö", START_ALTITUDE_M)

func _jump_to_city(city: String, altitude_m: float = 4500.0) -> void:
	if _coordinates == null or _camera_rig == null or not CITY_ABSOLUTE.has(city):
		return
	_current_city = city
	_current_world = _coordinates.absolute_to_world(CITY_ABSOLUTE[city], 0.0)
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
	_stress_step = 0
	_stress_button.text = "Stop stress cycle"
	_jump_to_city(CITY_ORDER[_stress_step], 4500.0)
	_stress_timer.start()

func _advance_stress() -> void:
	if _stress_step < 0:
		return
	_stress_step += 1
	if _stress_step >= CITY_ORDER.size():
		_stop_stress()
		return
	_jump_to_city(CITY_ORDER[_stress_step], 4500.0)

func _stop_stress() -> void:
	_stress_step = -1
	if _stress_timer != null:
		_stress_timer.stop()
	if _stress_button != null:
		_stress_button.text = "Stress: Malmö → Göteborg → Stockholm → Malmö"

func _update_controls() -> void:
	if _manual_button == null or _camera_rig == null:
		return
	var driving := bool(_camera_rig.call("is_driving_view"))
	var altitude := float(_camera_rig.call("get_altitude"))
	_manual_button.disabled = driving or altitude > MANUAL_READY_ALTITUDE_M
	_manual_button.text = "Manual Drive" if altitude <= MANUAL_READY_ALTITUDE_M else "Manual Drive (descend below 5 km)"
	_map_button.disabled = not driving

func _update_status() -> void:
	var driving := bool(_camera_rig.call("is_driving_view"))
	var altitude := float(_camera_rig.call("get_altitude"))
	var snapshot: Dictionary = _buildings.call("debug_snapshot") if _buildings != null else {}
	var cache_ready := FileAccess.file_exists("res://.poc_runtime/buildings/poc_manifest.json")
	var tile_ids: Array = snapshot.get("active_tile_ids", [])
	var tiles_text := ", ".join(tile_ids)
	if tiles_text.length() > 90:
		tiles_text = tiles_text.left(87) + "…"
	_status.text = "%s — reusable world streaming POC\nAltitude: %.0f m   FPS: %d\nTiles: %d active / %d pending / %d wanted   Records: %d\nBuild max: %.2f ms   Dropped requests: %d\nCenter tile: %s   Active: %s\nMode: %s   Cache: %s" % [
		_current_city,
		altitude,
		Engine.get_frames_per_second(),
		int(snapshot.get("active_tiles", 0)),
		int(snapshot.get("pending_tiles", 0)),
		int(snapshot.get("wanted_tiles", 0)),
		int(snapshot.get("active_records", 0)),
		float(_last_metrics.get("building_build_max_ms", 0.0)),
		int(_last_metrics.get("building_dropped_requests", 0)),
		String(snapshot.get("last_center_tile", "")),
		tiles_text,
		"MANUAL DRIVE" if driving else "MAP",
		"existing buildings.jsonl" if cache_ready else "MISSING",
	]

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16.0, 16.0)
	panel.custom_minimum_size = Vector2(520.0, 0.0)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var title := Label.new()
	title.text = "BRUR — World streaming POC #122"
	box.add_child(title)
	_status = Label.new()
	_status.text = "Preparing existing building data…"
	box.add_child(_status)
	_manual_button = Button.new()
	_manual_button.text = "Manual Drive (descend below 5 km)"
	_manual_button.pressed.connect(_enter_manual_drive)
	box.add_child(_manual_button)
	_map_button = Button.new()
	_map_button.text = "Return to map"
	_map_button.pressed.connect(_return_to_map)
	box.add_child(_map_button)
	_stress_button = Button.new()
	_stress_button.text = "Stress: Malmö → Göteborg → Stockholm → Malmö"
	_stress_button.pressed.connect(_start_stress)
	box.add_child(_stress_button)
	var reset := Button.new()
	reset.text = "Reset Malmö overview"
	reset.pressed.connect(_reset_overview)
	box.add_child(reset)
	var hint := Label.new()
	hint.text = "Mouse wheel: zoom   Drag/WASD: map\nManual Drive: W/S throttle, A/D steer, Space brake\nStress cycle pauses 2 s per city so streaming/unload can be inspected."
	box.add_child(hint)
	_stress_timer = Timer.new()
	_stress_timer.wait_time = 2.0
	_stress_timer.one_shot = false
	_stress_timer.timeout.connect(_advance_stress)
	add_child(_stress_timer)
