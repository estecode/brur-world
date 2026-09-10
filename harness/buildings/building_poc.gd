extends Node

## Composes the production map renderer, building stream layer, camera, and player vehicle for the #120 POC.
##
## Dependencies:
## - Uses the parent production world renderer for existing BRUR map data and shared coordinates.
## - Uses production BuildingStreamLayer, CameraRig, and player_vehicle scene; owns only harness controls/status.

const PlayerVehicleScene = preload("res://scenes/player_vehicle.tscn")
const MALMO_ABSOLUTE := Vector2(1447576.3943775708, 7480180.845685549)
const START_ALTITUDE_M: float = 180000.0
const MANUAL_READY_ALTITUDE_M: float = 5000.0
const PLAYER_HEIGHT_M: float = 24.8

var _main: Node = null
var _camera_rig: Node = null
var _buildings: Node = null
var _player: Node3D = null
var _manual_button: Button = null
var _map_button: Button = null
var _status: Label = null
var _metrics_accum: float = 0.0
var _malmo_world := Vector3.ZERO

func _ready() -> void:
	_build_ui()
	call_deferred("_initialize")

func _initialize() -> void:
	_main = get_parent()
	_camera_rig = _main.get_node("CameraRig")
	_buildings = _main.get_node("BuildingLayer")
	var coordinates = _main.call("get_world_coordinates")
	_malmo_world = coordinates.absolute_to_world(MALMO_ABSOLUTE, 0.0)
	_buildings.call("setup", coordinates, _camera_rig)
	_spawn_player()
	_camera_rig.call("set_view_altitude", _malmo_world, START_ALTITUDE_M)
	_update_controls()

func _process(delta: float) -> void:
	if _camera_rig == null:
		return
	_update_controls()
	_metrics_accum += delta
	if _metrics_accum < 0.25:
		return
	_metrics_accum = 0.0
	_update_status()

func _spawn_player() -> void:
	_player = PlayerVehicleScene.instantiate() as Node3D
	_player.name = "PocPlayerVehicle"
	_main.add_child(_player)
	_player.call("set_world_position", Vector3(_malmo_world.x, PLAYER_HEIGHT_M, _malmo_world.z))
	_player.call("set_motion_state", 0.0, -0.55)
	_player.visible = false
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_camera_rig.call("set_follow_target", _player)

func _enter_manual_drive() -> void:
	if _camera_rig == null or _player == null:
		return
	if float(_camera_rig.call("get_altitude")) > MANUAL_READY_ALTITUDE_M:
		return
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
	_camera_rig.call("set_view_altitude", _malmo_world, 4500.0)
	_update_controls()

func _reset_overview() -> void:
	if _camera_rig == null:
		return
	_camera_rig.call("set_drive_mode", false)
	if _player != null:
		_player.process_mode = Node.PROCESS_MODE_DISABLED
		_player.visible = false
		_player.call("set_world_position", Vector3(_malmo_world.x, PLAYER_HEIGHT_M, _malmo_world.z))
		_player.call("set_motion_state", 0.0, -0.55)
	_camera_rig.call("set_view_altitude", _malmo_world, START_ALTITUDE_M)
	_update_controls()

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
	var active_tiles := int(_buildings.call("active_tile_count")) if _buildings != null else 0
	var pending_tiles := int(_buildings.call("pending_tile_count")) if _buildings != null else 0
	var cache_ready := FileAccess.file_exists("res://.poc_runtime/buildings/poc_manifest.json")
	_status.text = "Malmö OSM 3D POC\nAltitude: %.0f m   FPS: %d\nBuildings: %d tile mesh(es), %d pending\nMode: %s   Cache: %s" % [
		altitude,
		Engine.get_frames_per_second(),
		active_tiles,
		pending_tiles,
		"MANUAL DRIVE" if driving else "MAP",
		"existing buildings.jsonl" if cache_ready else "MISSING",
	]

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(16.0, 16.0)
	panel.custom_minimum_size = Vector2(360.0, 0.0)
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
	title.text = "BRUR — Malmö 3D buildings POC"
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
	var reset := Button.new()
	reset.text = "Reset Malmö overview"
	reset.pressed.connect(_reset_overview)
	box.add_child(reset)
	var hint := Label.new()
	hint.text = "Mouse wheel: zoom   Drag/WASD: map\nManual Drive: W/S throttle, A/D steer, Space brake"
	box.add_child(hint)
