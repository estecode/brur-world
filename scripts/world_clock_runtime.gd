extends Node
class_name WorldClockRuntime

## Owns the production WorldClock instance and advances it from Godot frame time.
## Dependencies: scripts/world_clock.gd and Godot Time only for initial UTC bootstrap; consumers read the clock through explicit APIs.

const WorldClockScript = preload("res://scripts/world_clock.gd")

@export var speed_multiplier := 1.0

var _clock

func _ready() -> void:
	var utc_now: Dictionary = Time.get_datetime_dict_from_system(true)
	_clock = WorldClockScript.new(
		int(utc_now.get("year", 2026)),
		int(utc_now.get("month", 1)),
		int(utc_now.get("day", 1)),
		int(utc_now.get("hour", 0)),
		int(utc_now.get("minute", 0)),
		float(utc_now.get("second", 0))
	)
	_clock.set_speed_multiplier(speed_multiplier)

func _process(delta: float) -> void:
	if _clock != null:
		_clock.advance(delta)

func get_clock():
	return _clock

func get_utc_snapshot() -> Dictionary:
	if _clock == null:
		return {"valid": false}
	return {
		"year": _clock.get_year(),
		"month": _clock.get_month(),
		"day": _clock.get_day(),
		"hour": _clock.get_hour(),
		"minute": _clock.get_minute(),
		"second": _clock.get_second(),
		"utc_offset_hours": 0.0,
	}
