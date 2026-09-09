class_name MapControlsUi
extends CanvasLayer

## Presents small map/debug controls and forwards intent through explicit production APIs.
##
## Dependencies:
## - Scene composition supplies PoiLayer, GpsRouteLayer and CameraRig paths.
## - Owns no POI data, vehicle state, GPS route state, coordinate conversion, or camera simulation.

const LUND_FOCUS: Vector3 = Vector3(-489086.0, 0.0, 1582123.0)
const LUND_DISTANCE: float = 12472.0

@export var poi_layer_path: NodePath
@export var gps_route_layer_path: NodePath
@export var camera_rig_path: NodePath

var _poi_layer: Node
var _gps_route_layer: Node
var _camera_rig: Node
var _poi_toggle: CheckButton
var _teleport_toggle: CheckButton
var _follow_car_toggle: CheckButton

func _ready() -> void:
	layer = 70
	_poi_layer = get_node_or_null(poi_layer_path)
	_gps_route_layer = get_node_or_null(gps_route_layer_path)
	_camera_rig = get_node_or_null(camera_rig_path)
	_build_ui()
	if _gps_route_layer != null and _gps_route_layer.has_signal("teleport_state_changed"):
		_gps_route_layer.connect("teleport_state_changed", set_teleport_armed)

func set_teleport_armed(armed: bool) -> void:
	_ensure_ui()
	_teleport_toggle.set_pressed_no_signal(armed)
	_teleport_toggle.text = "Teleport: ARMED" if armed else "Teleport"

func set_follow_car_enabled(enabled: bool) -> void:
	_ensure_ui()
	_follow_car_toggle.set_pressed_no_signal(enabled)

func set_poi_visible(visible: bool) -> void:
	_ensure_ui()
	_poi_toggle.set_pressed_no_signal(visible)

func _build_ui() -> void:
	if _poi_toggle != null:
		return
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 14.0
	panel.offset_top = -58.0
	panel.offset_right = 570.0
	panel.offset_bottom = -14.0
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	_poi_toggle = CheckButton.new()
	_poi_toggle.text = "Show POIs"
	_poi_toggle.button_pressed = true
	_poi_toggle.tooltip_text = "Hide/show POI markers and hover only; POI search stays available"
	_poi_toggle.toggled.connect(_on_poi_toggled)
	row.add_child(_poi_toggle)

	_teleport_toggle = CheckButton.new()
	_teleport_toggle.text = "Teleport"
	_teleport_toggle.tooltip_text = "Arm one teleport; the next valid map click moves the player car and disarms"
	_teleport_toggle.toggled.connect(_on_teleport_toggled)
	row.add_child(_teleport_toggle)

	_follow_car_toggle = CheckButton.new()
	_follow_car_toggle.text = "Follow car"
	_follow_car_toggle.button_pressed = true
	_follow_car_toggle.tooltip_text = "Center and follow the player car; independent from Follow route"
	_follow_car_toggle.toggled.connect(_on_follow_car_toggled)
	row.add_child(_follow_car_toggle)

	var lund := Button.new()
	lund.text = "Lund"
	lund.tooltip_text = "Focus Lund at the saved gameplay zoom"
	lund.pressed.connect(_focus_lund)
	row.add_child(lund)

func _ensure_ui() -> void:
	if _poi_toggle == null:
		_build_ui()

func _on_poi_toggled(visible: bool) -> void:
	if _poi_layer != null and _poi_layer.has_method("set_presentation_enabled"):
		_poi_layer.call("set_presentation_enabled", visible)

func _on_teleport_toggled(armed: bool) -> void:
	set_teleport_armed(armed)
	if _gps_route_layer != null and _gps_route_layer.has_method("set_teleport_armed"):
		_gps_route_layer.call("set_teleport_armed", armed)

func _on_follow_car_toggled(enabled: bool) -> void:
	if _camera_rig == null or _gps_route_layer == null:
		return
	var player_value: Variant = _gps_route_layer.call("get_player_vehicle")
	if not (player_value is Node3D):
		return
	var player := player_value as Node3D
	if enabled:
		var current_distance: float = float(_camera_rig.call("get_distance"))
		_camera_rig.call("set_follow_target", player)
		_camera_rig.call("set_view", player.global_position, current_distance)
	else:
		_camera_rig.call("clear_follow_target")

func _focus_lund() -> void:
	if _camera_rig == null:
		return
	_follow_car_toggle.set_pressed_no_signal(false)
	_camera_rig.call("clear_follow_target")
	_camera_rig.call("set_view", LUND_FOCUS, LUND_DISTANCE)
