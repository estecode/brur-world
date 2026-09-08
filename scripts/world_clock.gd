##
## Owns deterministic game-world date/time and serializable clock state.
##
## Dependencies:
## - Uses only basic GDScript value types.
## - Does not depend on SceneTree, rendering, persistence I/O, or gameplay systems.
##
extends RefCounted

class_name WorldClock

const SECONDS_PER_DAY := 86400.0
const WEEKDAY_MONDAY := 1
const WEEKDAY_SUNDAY := 7

var _year: int
var _month: int
var _day: int
var _seconds_of_day: float
var _speed_multiplier: float = 1.0
var _paused: bool = false


func _init(
	start_year: int = 2026,
	start_month: int = 1,
	start_day: int = 1,
	start_hour: int = 0,
	start_minute: int = 0,
	start_second: float = 0.0
) -> void:
	_set_datetime(start_year, start_month, start_day, start_hour, start_minute, start_second)


func advance(real_delta_seconds: float) -> void:
	assert(real_delta_seconds >= 0.0)
	if _paused or real_delta_seconds == 0.0:
		return

	_seconds_of_day += real_delta_seconds * _speed_multiplier
	while _seconds_of_day >= SECONDS_PER_DAY:
		_seconds_of_day -= SECONDS_PER_DAY
		_advance_one_day()


func set_speed_multiplier(multiplier: float) -> void:
	assert(multiplier >= 0.0)
	_speed_multiplier = multiplier


func get_speed_multiplier() -> float:
	return _speed_multiplier


func set_paused(paused: bool) -> void:
	_paused = paused


func is_paused() -> bool:
	return _paused


func get_year() -> int:
	return _year


func get_month() -> int:
	return _month


func get_day() -> int:
	return _day


func get_hour() -> int:
	return int(floor(_seconds_of_day / 3600.0))


func get_minute() -> int:
	return int(floor(fmod(_seconds_of_day, 3600.0) / 60.0))


func get_second() -> int:
	return int(floor(fmod(_seconds_of_day, 60.0)))


func get_seconds_of_day() -> float:
	return _seconds_of_day


func get_weekday() -> int:
	# 1970-01-01 was Thursday. Convert to Monday=1 ... Sunday=7.
	var days_since_epoch := _date_day_number(_year, _month, _day) - _date_day_number(1970, 1, 1)
	return posmod(days_since_epoch + 3, 7) + 1


func is_weekend() -> bool:
	return get_weekday() >= 6


func is_weekday() -> bool:
	return not is_weekend()


func get_daypart() -> StringName:
	var hour := get_hour()
	if hour >= 5 and hour < 10:
		return &"morning"
	if hour >= 10 and hour < 18:
		return &"day"
	if hour >= 18 and hour < 23:
		return &"evening"
	return &"night"


func is_daytime() -> bool:
	var hour := get_hour()
	return hour >= 6 and hour < 22


func save_state() -> Dictionary:
	return {
		"year": _year,
		"month": _month,
		"day": _day,
		"seconds_of_day": _seconds_of_day,
		"speed_multiplier": _speed_multiplier,
		"paused": _paused,
	}


func load_state(state: Dictionary) -> void:
	assert(state.has("year"))
	assert(state.has("month"))
	assert(state.has("day"))
	assert(state.has("seconds_of_day"))
	assert(state.has("speed_multiplier"))
	assert(state.has("paused"))

	var seconds_of_day := float(state["seconds_of_day"])
	assert(seconds_of_day >= 0.0 and seconds_of_day < SECONDS_PER_DAY)
	var hour := int(floor(seconds_of_day / 3600.0))
	var minute := int(floor(fmod(seconds_of_day, 3600.0) / 60.0))
	var second := fmod(seconds_of_day, 60.0)
	_set_datetime(int(state["year"]), int(state["month"]), int(state["day"]), hour, minute, second)
	set_speed_multiplier(float(state["speed_multiplier"]))
	_paused = bool(state["paused"])


func _set_datetime(year: int, month: int, day: int, hour: int, minute: int, second: float) -> void:
	assert(year >= 1)
	assert(month >= 1 and month <= 12)
	assert(day >= 1 and day <= _days_in_month(year, month))
	assert(hour >= 0 and hour <= 23)
	assert(minute >= 0 and minute <= 59)
	assert(second >= 0.0 and second < 60.0)

	_year = year
	_month = month
	_day = day
	_seconds_of_day = float(hour * 3600 + minute * 60) + second


func _advance_one_day() -> void:
	_day += 1
	if _day <= _days_in_month(_year, _month):
		return
	_day = 1
	_month += 1
	if _month <= 12:
		return
	_month = 1
	_year += 1


static func _days_in_month(year: int, month: int) -> int:
	match month:
		1, 3, 5, 7, 8, 10, 12:
			return 31
		4, 6, 9, 11:
			return 30
		2:
			return 29 if _is_leap_year(year) else 28
	return 0


static func _is_leap_year(year: int) -> bool:
	return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


static func _date_day_number(year: int, month: int, day: int) -> int:
	var previous_year := year - 1
	var result := previous_year * 365
	result += int(previous_year / 4.0)
	result -= int(previous_year / 100.0)
	result += int(previous_year / 400.0)
	for candidate_month in range(1, month):
		result += _days_in_month(year, candidate_month)
	return result + day - 1
