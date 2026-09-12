class_name MapControlsUi
extends CanvasLayer

## Presents small map/debug controls and forwards intent through explicit production APIs.
##
## Dependencies:
## - Scene composition supplies PoiLayer, BuildingStreamLayer, GpsRouteLayer and CameraRig paths.
## - Owns no POI/building data, vehicle state, GPS route state, coordinate conversion, or camera simulation.

@export var poi_layer_path: NodePath
@export var building_layer_path: NodePath
@export var gps_route_layer_path: NodePath
@export var camera_rig_path: NodePath

var _poi_layer: Node
var _building_layer: Node
var _gps_route_layer: Node
var _camera_rig: Node
var _poi_toggle: CheckButton
var _building_toggle: CheckButton
var _teleport_toggle: CheckButton
var _follow_car_toggle: CheckButton
var _drive_mode_toggle: CheckButton

func _ready() -> void:
	layer = 70
	_poi_layer = get_node_or_null(poi_layer_path)
	_building_layer = get_node_or_null(building_layer_path)
	_gps_route_layer = get_node_or_null(gps_route_layer_path)
	_camera_rig = get_node_or_null(camera_rig_path)
	_build_ui()
	_on_poi_toggled(false)
	_on_buildings_toggled(false)
	if _gps_route_layer != null and _gps_route_layer.has_signal("teleport_state_changed"):
		_gps_route_layer.connect("teleport_state_changed", set_teleport_armed)
	if _camera_rig != null and _camera_rig.has_signal("map_follow_changed"):
		_camera_rig.connect("map_follow_changed", set_follow_car_enabled)

func set_teleport_armed(armed: bool) -> void:
	_ensure_ui()
	_teleport_toggle.set_pressed_no_signal(armed)
	_teleport_toggle.text = "Teleport: ARMED" if armed else "Teleport"

func set_follow_car_enabled(enabled: bool) -> void:
	_ensure_ui()
	_follow_car_toggle.set_pressed_no_signal(enabled)

func set_drive_mode_enabled(enabled: bool) -> void:
	_ensure_ui()
	_drive_mode_toggle.set_pressed_no_signal(enabled)
	_follow_car_toggle.disabled = enabled
	if enabled:
		_follow_car_toggle.set_pressed_no_signal(false)

func set_poi_visible(visible: bool) -> void:
	_ensure_ui()
	_poi_toggle.set_pressed_no_signal(visible)

func set_buildings_visible(visible: bool) -> void:
	_ensure_ui()
	_building_toggle.set_pressed_no_signal(visible)
	_on_buildings_toggled(visible)

func _build_ui() -> void:
	if _poi_toggle != null:
		return
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 14.0
	panel.offset_top = -58.0
	panel.offset_right = 680.0
	panel.offset_bottom = -14.0
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	_poi_toggle = CheckButton.new()
	_poi_toggle.text = "Show POIs"
	_poi_toggle.button_pressed = false
	_poi_toggle.tooltip_text = "Hide/show POI markers and hover only; POI search stays available"
	_poi_toggle.toggled.connect(_on_poi_toggled)
	row.add_child(_poi_toggle)

	_building_toggle = CheckButton.new()
	_building_toggle.text = "HUS"
	_building_toggle.button_pressed = false
	_building_toggle.tooltip_text = "Stream and render nearby buildings; off by default for performance"
	_building_toggle.toggled.connect(_on_buildings_toggled)
	row.add_child(_building_toggle)

	_teleport_toggle = CheckButton.new()
	_teleport_toggle.text = "Teleport"
	_teleport_toggle.tooltip_text = "Arm one teleport; the next valid map click moves the player car and disarms"
	_teleport_toggle.toggled.connect(_on_teleport_toggled)
	row.add_child(_teleport_toggle)

	_follow_car_toggle = CheckButton.new()
	_follow_car_toggle.text = "Follow car"
	_follow_car_toggle.button_pressed = false
	_follow_car_toggle.tooltip_text = "Center and follow the player car in Map mode; panning disengages follow"
	_follow_car_toggle.toggled.connect(_on_follow_car_toggled)
	row.add_child(_follow_car_toggle)

	_drive_mode_toggle = CheckButton.new()
	_drive_mode_toggle.text = "Drive mode"
	_drive_mode_toggle.button_pressed = false
	_drive_mode_toggle.tooltip_text = "Behind-car driving camera; use W/S/A/D + Space to drive and the mouse wheel to adjust camera distance"
	_drive_mode_toggle.toggled.connect(_on_drive_mode_toggled)
	row.add_child(_drive_mode_toggle)

func _ensure_ui() -> void:
	if _poi_toggle == null:
		_build_ui()

func _on_poi_toggled(visible: bool) -> void:
	if _poi_layer != null and _poi_layer.has_method("set_presentation_enabled"):
		_poi_layer.call("set_presentation_enabled", visible)

func _on_buildings_toggled(visible: bool) -> void:
	if _building_layer != null and _building_layer.has_method("set_streaming_enabled"):
		_building_layer.call("set_streaming_enabled", visible)

func _on_teleport_toggled(armed: bool) -> void:
	set_teleport_armed(armed)
	if _gps_route_layer != null and _gps_route_layer.has_method("set_teleport_armed"):
		_gps_route_layer.call("set_teleport_armed", armed)

func _on_follow_car_toggled(enabled: bool) -> void:
	if _camera_rig == null or not _camera_rig.has_method("set_map_follow_enabled"):
		return
	_camera_rig.call("set_map_follow_enabled", enabled)

func _on_drive_mode_toggled(enabled: bool) -> void:
	set_drive_mode_enabled(enabled)
	if _camera_rig != null and _camera_rig.has_method("set_drive_mode"):
		_camera_rig.call("set_drive_mode", enabled)
