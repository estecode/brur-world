class_name SpeedLimitSign
extends Control

## Draws the Swedish circular speed-limit sign for an optional numeric limit.
##
## Dependencies:
## - Presentation only; receives an already-resolved speed limit from its owner.
## - Does not inspect road, routing, vehicle, or navigation state.

var _speed_limit_kmh: Variant = null

func _ready() -> void:
	custom_minimum_size = Vector2(72.0, 72.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_speed_limit_kmh(value: Variant) -> void:
	_speed_limit_kmh = value
	queue_redraw()

func displayed_text() -> String:
	if _speed_limit_kmh == null:
		return "—"
	return str(clampi(roundi(float(_speed_limit_kmh)), 0, 999))

func _draw() -> void:
	var radius: float = maxf(8.0, minf(size.x, size.y) * 0.5 - 4.0)
	var center := size * 0.5
	draw_circle(center, radius, Color(0.98, 0.96, 0.80, 1.0))
	draw_arc(center, radius - 2.5, 0.0, TAU, 64, Color(0.82, 0.02, 0.03, 1.0), 6.0, true)
	var text := displayed_text()
	var font: Font = ThemeDB.fallback_font
	var font_size := 25
	if text.length() >= 3:
		font_size = 21
	draw_string(font, Vector2(0.0, center.y + float(font_size) * 0.36), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, Color.BLACK)
