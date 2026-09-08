extends SceneTree

## Headless deterministic contract tests for WorldClock and weekly schedule queries.
## Dependencies: scripts/world_clock.gd and scripts/weekly_schedule.gd only.

const WorldClockScript = preload("res://scripts/world_clock.gd")
const WeeklyScheduleScript = preload("res://scripts/weekly_schedule.gd")

class TimeAwareFixture:
	extends RefCounted
	var clock
	var schedule

	func _init(clock_value, schedule_value) -> void:
		clock = clock_value
		schedule = schedule_value

	func is_active() -> bool:
		return schedule.is_active(clock)


func _init() -> void:
	_test_advancement_and_speed()
	_test_rollovers_and_calendar_queries()
	_test_pause_and_dayparts()
	_test_schedule_boundaries_and_shared_clock()
	_test_overnight_schedule()
	_test_deterministic_replay()
	_test_save_load_exact_state()
	print("godot world-clock tests: OK")
	quit(0)


func _test_advancement_and_speed() -> void:
	var clock = WorldClockScript.new(2026, 9, 7, 8, 0, 0.0)
	clock.advance(30.0)
	_assert(clock.get_hour() == 8 and clock.get_minute() == 0 and clock.get_second() == 30, "clock advances by real delta at 1x")
	clock.set_speed_multiplier(10.0)
	clock.advance(9.0)
	_assert(clock.get_hour() == 8 and clock.get_minute() == 2 and clock.get_second() == 0, "speed multiplier scales advancement")


func _test_rollovers_and_calendar_queries() -> void:
	var clock = WorldClockScript.new(2026, 9, 7, 23, 59, 59.0)
	_assert(clock.get_weekday() == WorldClockScript.WEEKDAY_MONDAY, "known Monday reports Monday")
	_assert(clock.is_weekday(), "Monday is a weekday")
	clock.advance(1.0)
	_assert(clock.get_year() == 2026 and clock.get_month() == 9 and clock.get_day() == 8, "day rolls over at midnight")
	_assert(clock.get_weekday() == 2, "weekday rolls over with date")

	var month_clock = WorldClockScript.new(2028, 2, 28, 23, 59, 59.0)
	month_clock.advance(1.0)
	_assert(month_clock.get_month() == 2 and month_clock.get_day() == 29, "leap day is preserved")
	month_clock.advance(86400.0)
	_assert(month_clock.get_month() == 3 and month_clock.get_day() == 1, "month rolls over after leap day")

	var weekend = WorldClockScript.new(2026, 9, 12, 12, 0, 0.0)
	_assert(weekend.is_weekend(), "Saturday is a weekend")


func _test_pause_and_dayparts() -> void:
	var clock = WorldClockScript.new(2026, 9, 7, 4, 59, 59.0)
	_assert(clock.get_daypart() == &"night", "pre-morning time is night")
	_assert(not clock.is_daytime(), "pre-dawn is not daytime")
	clock.advance(1.0)
	_assert(clock.get_daypart() == &"morning", "05:00 starts morning")
	clock.advance(3600.0)
	_assert(clock.is_daytime(), "06:00 starts daytime")
	clock.set_paused(true)
	var before := clock.save_state()
	clock.advance(12345.0)
	_assert(clock.save_state() == before, "paused clock does not advance")
	clock.set_paused(false)
	clock.advance(1.0)
	_assert(clock.get_second() == 1, "clock resumes after pause")


func _test_schedule_boundaries_and_shared_clock() -> void:
	var clock = WorldClockScript.new(2026, 9, 7, 7, 59, 59.0)
	var contact_schedule = WeeklyScheduleScript.new([
		{"days": [1, 2, 3, 4, 5], "start_minute": 8 * 60, "end_minute": 17 * 60},
	])
	var traffic_schedule = WeeklyScheduleScript.new([
		{"days": [1, 2, 3, 4, 5], "start_minute": 8 * 60, "end_minute": 10 * 60},
	])
	var contact = TimeAwareFixture.new(clock, contact_schedule)
	var traffic = TimeAwareFixture.new(clock, traffic_schedule)

	_assert(not contact.is_active() and not traffic.is_active(), "fixtures are inactive before shared schedule boundary")
	clock.advance(1.0)
	_assert(contact.is_active() and traffic.is_active(), "contact and traffic fixtures react to the same clock at opening boundary")
	clock.advance(2.0 * 3600.0)
	_assert(contact.is_active(), "contact remains active inside its window")
	_assert(not traffic.is_active(), "traffic fixture closes exactly at its end boundary")


func _test_overnight_schedule() -> void:
	var clock = WorldClockScript.new(2026, 9, 7, 21, 59, 59.0)
	var police_schedule = WeeklyScheduleScript.new([
		{"days": [1], "start_minute": 22 * 60, "end_minute": 6 * 60},
	])
	_assert(not police_schedule.is_active(clock), "overnight schedule is inactive before start")
	clock.advance(1.0)
	_assert(police_schedule.is_active(clock), "overnight schedule activates at start")
	clock.advance(3.0 * 3600.0)
	_assert(police_schedule.is_active(clock), "overnight schedule carries into next weekday")
	clock.advance(6.0 * 3600.0)
	_assert(not police_schedule.is_active(clock), "overnight schedule ends at exact boundary")


func _test_deterministic_replay() -> void:
	var a = WorldClockScript.new(2026, 1, 31, 23, 50, 0.25)
	var b = WorldClockScript.new(2026, 1, 31, 23, 50, 0.25)
	a.set_speed_multiplier(7.5)
	b.set_speed_multiplier(7.5)
	for delta in [0.1, 1.0, 17.25, 90.0, 5000.5]:
		a.advance(delta)
		b.advance(delta)
	_assert(a.save_state() == b.save_state(), "identical input sequence produces identical clock state")


func _test_save_load_exact_state() -> void:
	var original = WorldClockScript.new(2026, 12, 31, 23, 59, 58.375)
	original.set_speed_multiplier(3.25)
	original.advance(0.125)
	original.set_paused(true)
	var saved := original.save_state()

	var restored = WorldClockScript.new()
	restored.load_state(saved)
	_assert(restored.save_state() == saved, "save/load restores exact world time, speed, and pause state")
	_assert(restored.get_weekday() == original.get_weekday(), "restored calendar queries match original")


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("world-clock test failed: " + message)
	quit(1)
