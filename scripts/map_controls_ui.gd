class_name MapControlsUi
extends CanvasLayer

## Presents small map/debug controls and emits user intent without owning world, vehicle, POI, GPS, or camera behavior.
##
## Dependencies:
## - Main composition wires emitted intents to PoiLayer, GpsRouteLayer and CameraRig public APIs.

signal poi_visibility_changed(visible: bool)
signal teleport_armed_changed(armed: bool)
signal follow_car_changed(enabled: bool)
signal focus_lund_requested

var _poi_toggle: CheckButton
var _teleport_toggle: CheckButton
var _follow_car_toggle: CheckButton

func _ready() -> void:
	layer = 70
	_build_ui()

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
	row.theme_override_constants.separation = 8
	panel.add_child(row)

	_poi_toggle = CheckButton.new()
	_poi_toggle.text = "Show POIs"
	_poi_toggle.button_pressed = true
	_poi_toggle.tooltip_text = "Hide/show POI markers and hover only; POI search stays available"
	_poi_toggle.toggled.connect(func(value: bool) -> void: poi_visibility_changed.emit(value))
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
	_follow_car_toggle.toggled.connect(func(value: bool) -> void: follow_car_changed.emit(value))
	row.add_child(_follow_car_toggle)

	var lund := Button.new()
	lund.text = "Lund"
	lund.tooltip_text = "Focus Lund at the saved gameplay zoom"
	lund.pressed.connect(func() -> void: focus_lund_requested.emit())
	row.add_child(lund)

func _ensure_ui() -> void:
	if _poi_toggle == null:
		_build_ui()

func _on_teleport_toggled(armed: bool) -> void:
	set_teleport_armed(armed)
	teleport_armed_changed.emit(armed)
