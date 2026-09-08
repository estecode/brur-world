##
## Answers whether a weekly time window is active for a supplied WorldClock.
##
## Dependencies:
## - Consumes the public WorldClock time API.
## - Does not own time or depend on traffic, police, contacts, UI, or persistence.
##
extends RefCounted

class_name WeeklySchedule

var _windows: Array[Dictionary] = []


func _init(windows: Array[Dictionary] = []) -> void:
	for window in windows:
		add_window(window["days"], int(window["start_minute"]), int(window["end_minute"]))


func add_window(days: Array, start_minute: int, end_minute: int) -> void:
	assert(start_minute >= 0 and start_minute < 1440)
	assert(end_minute >= 0 and end_minute <= 1440)
	assert(start_minute != end_minute)

	var normalized_days: Array[int] = []
	for day in days:
		var weekday := int(day)
		assert(weekday >= WorldClock.WEEKDAY_MONDAY and weekday <= WorldClock.WEEKDAY_SUNDAY)
		if not normalized_days.has(weekday):
			normalized_days.append(weekday)

	assert(not normalized_days.is_empty())
	_windows.append({
		"days": normalized_days,
		"start_second": float(start_minute * 60),
		"end_second": float(end_minute * 60),
	})


func is_active(clock: WorldClock) -> bool:
	var weekday := clock.get_weekday()
	var seconds_of_day := clock.get_seconds_of_day()
	for window in _windows:
		if _window_is_active(window, weekday, seconds_of_day):
			return true
	return false


func _window_is_active(window: Dictionary, weekday: int, seconds_of_day: float) -> bool:
	var days: Array = window["days"]
	var start_second := float(window["start_second"])
	var end_second := float(window["end_second"])

	if start_second < end_second:
		return days.has(weekday) and seconds_of_day >= start_second and seconds_of_day < end_second

	if days.has(weekday) and seconds_of_day >= start_second:
		return true
	var previous_weekday := weekday - 1
	if previous_weekday < WorldClock.WEEKDAY_MONDAY:
		previous_weekday = WorldClock.WEEKDAY_SUNDAY
	return days.has(previous_weekday) and seconds_of_day < end_second
