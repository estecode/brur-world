class_name DriveHudPresentation
extends CanvasLayer

## Presents Drive-mode speed, Swedish speed-limit sign, and optional route ETA.
##
## Dependencies:
## - Receives a small explicit view-state dictionary from DriveHudAdapter.
## - Owns layout/formatting only; it does not calculate vehicle, road, or route state.

const SpeedLimitSignScript = preload("res://scripts/speed_limit_sign.gd")
const SPEED_FIELD_WIDTH: float = 96.0
const ETA_FIELD_WIDTH: float = 112.0

var _panel: PanelContainer
var _row: HBoxContainer
var _sign: Control
var _speed_value: Label
var _speed_unit: Label
var _eta_separator: VSeparator
var _eta_box: VBoxContainer
var _eta_value: Label

func _ready() -> void:
	layer = 30
	_build_ui()
	set_drive_visible(false)

func set_drive_visible(enabled: bool) -> void:
	visible = enabled

func set_state(state: Dictionary) -> void:
	if _panel == null:
		_build_ui()
	_speed_value.text = format_speed_kmh(float(state.get("current_speed_kmh", 0.0)))
	_sign.call("set_speed_limit_kmh", state.get("speed_limit_kmh", null))
	var eta_value: Variant = state.get("eta_seconds", null)
	var has_eta := eta_value != null and is_finite(float(eta_value)) and float(eta_value) >= 0.0
	_eta_separator.visible = has_eta
	_eta_box.visible = has_eta
	if has_eta:
		_eta_value.text = format_eta(float(eta_value))

func format_speed_kmh(value: float) -> String:
	return str(clampi(roundi(value), 0, 999))

func format_eta(seconds: float) -> String:
	var total_seconds := maxi(0, roundi(seconds))
	var hours := total_seconds / 3600
	var minutes := (total_seconds % 3600) / 60
	var secs := total_seconds % 60
	return "%02d:%02d:%02d" % [hours, minutes, secs]

func speed_field_width() -> float:
	return SPEED_FIELD_WIDTH

func eta_visible() -> bool:
	return _eta_box != null and _eta_box.visible

func speed_value_control() -> Label:
	return _speed_value

func eta_box_control() -> Control:
	return _eta_box

func speed_limit_sign_control() -> Control:
	return _sign

func _build_ui() -> void:
	if _panel != null:
		return
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_panel.offset_left = 24.0
	_panel.offset_top = -120.0
	_panel.offset_right = 282.0
	_panel.offset_bottom = -24.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.045, 0.055, 0.88)
	panel_style.corner_radius_top_left = 18
	panel_style.corner_radius_top_right = 18
	panel_style.corner_radius_bottom_left = 18
	panel_style.corner_radius_bottom_right = 18
	panel_style.content_margin_left = 12.0
	panel_style.content_margin_right = 12.0
	panel_style.content_margin_top = 8.0
	panel_style.content_margin_bottom = 8.0
	_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_panel)

	_row = HBoxContainer.new()
	_row.name = "Row"
	_row.add_theme_constant_override("separation", 12)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_row)

	_sign = SpeedLimitSignScript.new()
	_sign.name = "SpeedLimitSign"
	_sign.custom_minimum_size = Vector2(72.0, 72.0)
	_row.add_child(_sign)

	var first_separator := VSeparator.new()
	first_separator.name = "SpeedSeparator"
	_row.add_child(first_separator)

	var speed_box := VBoxContainer.new()
	speed_box.name = "Speed"
	speed_box.custom_minimum_size = Vector2(SPEED_FIELD_WIDTH, 72.0)
	speed_box.add_theme_constant_override("separation", -4)
	_row.add_child(speed_box)

	_speed_value = Label.new()
	_speed_value.name = "Value"
	_speed_value.text = "0"
	_speed_value.custom_minimum_size = Vector2(SPEED_FIELD_WIDTH, 48.0)
	_speed_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_value.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_speed_value.add_theme_font_size_override("font_size", 42)
	speed_box.add_child(_speed_value)

	_speed_unit = Label.new()
	_speed_unit.name = "Unit"
	_speed_unit.text = "km/h"
	_speed_unit.custom_minimum_size = Vector2(SPEED_FIELD_WIDTH, 20.0)
	_speed_unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_unit.add_theme_font_size_override("font_size", 18)
	speed_box.add_child(_speed_unit)

	_eta_separator = VSeparator.new()
	_eta_separator.name = "EtaSeparator"
	_row.add_child(_eta_separator)

	_eta_box = VBoxContainer.new()
	_eta_box.name = "Eta"
	_eta_box.custom_minimum_size = Vector2(ETA_FIELD_WIDTH, 72.0)
	_eta_box.add_theme_constant_override("separation", 1)
	_row.add_child(_eta_box)

	var eta_title := Label.new()
	eta_title.name = "Title"
	eta_title.text = "ETA"
	eta_title.add_theme_font_size_override("font_size", 15)
	_eta_box.add_child(eta_title)

	_eta_value = Label.new()
	_eta_value.name = "Value"
	_eta_value.text = "00:00:00"
	_eta_value.custom_minimum_size = Vector2(ETA_FIELD_WIDTH, 36.0)
	_eta_value.add_theme_font_size_override("font_size", 22)
	_eta_box.add_child(_eta_value)
