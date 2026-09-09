class_name GpsGuidanceCard
extends CanvasLayer

## Renders one compact Swedish-inspired road guidance card from navigation metadata.
##
## Dependencies:
## - GpsSignStyle owns deterministic metadata-to-presentation policy.
## - Consumes navigation metadata only; has no routing or transport dependency.

const SignStyle = preload("res://scripts/gps_sign_style.gd")

var _panel: PanelContainer
var _label: Label

func _ready() -> void:
	_build_ui()

func clear() -> void:
	_ensure_ui()
	_panel.visible = false
	_label.text = ""

func show_metadata(metadata: Dictionary) -> void:
	_ensure_ui()
	var text := SignStyle.label(metadata)
	if text.is_empty():
		clear()
		return
	var style := SignStyle.presentation(metadata)
	var box := StyleBoxFlat.new()
	box.bg_color = style["background"]
	box.border_color = style["border"]
	box.set_border_width_all(2)
	box.set_corner_radius_all(5)
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	box.content_margin_top = 7.0
	box.content_margin_bottom = 7.0
	_panel.add_theme_stylebox_override("panel", box)
	_label.add_theme_color_override("font_color", style["foreground"])
	_label.text = text
	_panel.visible = true

func displayed_text() -> String:
	_ensure_ui()
	return _label.text

func _build_ui() -> void:
	if _panel != null:
		return
	layer = 49
	_panel = PanelContainer.new()
	_panel.name = "GuidanceCard"
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.position = Vector2(-180.0, 16.0)
	_panel.custom_minimum_size = Vector2(360.0, 0.0)
	add_child(_panel)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 22)
	_panel.add_child(_label)
	_panel.visible = false

func _ensure_ui() -> void:
	if _panel == null:
		_build_ui()
