extends SceneTree

## Headless deterministic tests for astronomical solar position, seasonal daylight, polar cases, and the Godot light adapter.
## Dependencies: scripts/sun_position_model.gd and scripts/sun_light_adapter.gd only.

const SunPositionModelScript = preload("res://scripts/sun_position_model.gd")
const SunLightAdapterScript = preload("res://scripts/sun_light_adapter.gd")

const STOCKHOLM_LAT := 59.3293
const STOCKHOLM_LON := 18.0686
const MALMO_LAT := 55.6050
const MALMO_LON := 13.0038
const KIRUNA_LAT := 67.8558
const KIRUNA_LON := 20.2253

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_reference_stockholm_summer()
	_test_reference_stockholm_winter()
	_test_seasonal_difference()
	_test_geographic_difference_and_polar_cases()
	_test_time_progression()
	_test_invalid_inputs()
	await _test_godot_adapter()
	call_deferred("_finish")

func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("godot astronomical sun tests: OK")
	quit(0)

func _snapshot(year: int, month: int, day: int, hour: int, minute: int, utc_offset_hours: float) -> Dictionary:
	return {
		"year": year,
		"month": month,
		"day": day,
		"hour": hour,
		"minute": minute,
		"second": 0,
		"utc_offset_hours": utc_offset_hours,
	}

func _test_reference_stockholm_summer() -> void:
	var model = SunPositionModelScript.new()
	var first: Dictionary = model.calculate(_snapshot(2025, 6, 21, 13, 0, 2.0), STOCKHOLM_LAT, STOCKHOLM_LON)
	var second: Dictionary = model.calculate(_snapshot(2025, 6, 21, 13, 0, 2.0), STOCKHOLM_LAT, STOCKHOLM_LON)
	_assert(first == second, "same input is deterministic")
	_assert(bool(first["valid"]), "Stockholm summer reference is valid")
	# External solar-table reference for Stockholm 2025-06-21 reports about 54.1° elevation at 13:00 and 18h37m daylight.
	_assert(absf(float(first["elevation_deg"]) - 54.1) < 1.5, "Stockholm summer elevation matches reference tolerance")
	_assert(absf(float(first["daylight_minutes"]) - 1117.5) < 12.0, "Stockholm summer daylight matches reference tolerance")
	_assert(float(first["azimuth_deg"]) > 170.0 and float(first["azimuth_deg"]) < 200.0, "Stockholm summer sun is near south around local solar noon")

func _test_reference_stockholm_winter() -> void:
	var model = SunPositionModelScript.new()
	var state: Dictionary = model.calculate(_snapshot(2026, 12, 21, 11, 45, 1.0), STOCKHOLM_LAT, STOCKHOLM_LON)
	_assert(bool(state["valid"]), "Stockholm winter reference is valid")
	# Timeanddate/Swedish sun tables report about 7.3° solar-noon elevation and 6h05m daylight on 2026-12-21.
	_assert(absf(float(state["elevation_deg"]) - 7.3) < 1.2, "Stockholm winter elevation matches reference tolerance")
	_assert(absf(float(state["daylight_minutes"]) - 364.8) < 12.0, "Stockholm winter daylight matches reference tolerance")

func _test_seasonal_difference() -> void:
	var model = SunPositionModelScript.new()
	var summer: Dictionary = model.calculate(_snapshot(2026, 6, 21, 12, 45, 2.0), STOCKHOLM_LAT, STOCKHOLM_LON)
	var winter: Dictionary = model.calculate(_snapshot(2026, 12, 21, 11, 45, 1.0), STOCKHOLM_LAT, STOCKHOLM_LON)
	_assert(float(summer["elevation_deg"]) > float(winter["elevation_deg"]) + 40.0, "summer noon sun is substantially higher than winter")
	_assert(float(summer["daylight_minutes"]) > float(winter["daylight_minutes"]) + 600.0, "summer daylight is substantially longer than winter")

func _test_geographic_difference_and_polar_cases() -> void:
	var model = SunPositionModelScript.new()
	var malmo_summer: Dictionary = model.calculate(_snapshot(2026, 6, 21, 12, 30, 2.0), MALMO_LAT, MALMO_LON)
	var kiruna_summer: Dictionary = model.calculate(_snapshot(2026, 6, 21, 12, 45, 2.0), KIRUNA_LAT, KIRUNA_LON)
	var kiruna_winter: Dictionary = model.calculate(_snapshot(2026, 12, 21, 11, 30, 1.0), KIRUNA_LAT, KIRUNA_LON)
	_assert(not bool(malmo_summer["polar_day"]), "Malmö does not enter polar day")
	_assert(bool(kiruna_summer["polar_day"]), "Kiruna handles midnight sun as polar day")
	_assert(is_equal_approx(float(kiruna_summer["daylight_minutes"]), 1440.0), "Kiruna polar day is 24 hours")
	_assert(bool(kiruna_winter["polar_night"]), "Kiruna handles polar night")
	_assert(is_equal_approx(float(kiruna_winter["daylight_minutes"]), 0.0), "Kiruna polar night has zero sunrise-to-sunset daylight")
	_assert(float(malmo_summer["elevation_deg"]) > float(kiruna_summer["elevation_deg"]), "southern Sweden has a higher summer-noon sun than Kiruna")

func _test_time_progression() -> void:
	var model = SunPositionModelScript.new()
	var morning: Dictionary = model.calculate(_snapshot(2026, 6, 21, 8, 0, 2.0), STOCKHOLM_LAT, STOCKHOLM_LON)
	var noon: Dictionary = model.calculate(_snapshot(2026, 6, 21, 12, 45, 2.0), STOCKHOLM_LAT, STOCKHOLM_LON)
	var afternoon: Dictionary = model.calculate(_snapshot(2026, 6, 21, 17, 0, 2.0), STOCKHOLM_LAT, STOCKHOLM_LON)
	_assert(float(morning["azimuth_deg"]) < float(noon["azimuth_deg"]), "sun azimuth advances from morning to noon")
	_assert(float(noon["azimuth_deg"]) < float(afternoon["azimuth_deg"]), "sun azimuth advances from noon to afternoon")
	_assert(float(noon["elevation_deg"]) > float(morning["elevation_deg"]), "sun rises toward noon")
	_assert(float(noon["elevation_deg"]) > float(afternoon["elevation_deg"]), "sun falls after noon")

func _test_invalid_inputs() -> void:
	var model = SunPositionModelScript.new()
	_assert(not bool(model.calculate(_snapshot(2026, 2, 30, 12, 0, 1.0), STOCKHOLM_LAT, STOCKHOLM_LON)["valid"]), "invalid calendar date is rejected")
	_assert(not bool(model.calculate(_snapshot(2026, 6, 21, 12, 0, 1.0), 91.0, STOCKHOLM_LON)["valid"]), "invalid latitude is rejected")
	_assert(not bool(model.calculate(_snapshot(2026, 6, 21, 12, 0, 15.0), STOCKHOLM_LAT, STOCKHOLM_LON)["valid"]), "invalid UTC offset is rejected")

func _test_godot_adapter() -> void:
	var light := DirectionalLight3D.new()
	var adapter = SunLightAdapterScript.new()
	root.add_child(light)
	root.add_child(adapter)
	await process_frame
	adapter.setup(light)
	var model = SunPositionModelScript.new()
	var snapshot := _snapshot(2026, 6, 21, 9, 0, 2.0)
	var expected: Dictionary = model.calculate(snapshot, STOCKHOLM_LAT, STOCKHOLM_LON)
	var before_basis := light.global_transform.basis
	var actual: Dictionary = adapter.apply_time_snapshot(snapshot, STOCKHOLM_LAT, STOCKHOLM_LON)
	_assert(bool(actual["valid"]), "adapter accepts valid production solar state")
	_assert(is_equal_approx(float(actual["azimuth_deg"]), float(expected["azimuth_deg"])), "adapter returns production model azimuth")
	_assert(is_equal_approx(float(actual["elevation_deg"]), float(expected["elevation_deg"])), "adapter returns production model elevation")
	_assert(light.global_transform.basis != before_basis, "adapter rotates DirectionalLight3D")
	_assert(light.visible and light.light_energy > 0.0, "adapter enables daytime light energy")
	var night: Dictionary = adapter.apply_time_snapshot(_snapshot(2026, 12, 21, 2, 0, 1.0), STOCKHOLM_LAT, STOCKHOLM_LON)
	_assert(float(night["elevation_deg"]) < 0.0, "night fixture puts sun below horizon")
	_assert(not light.visible and is_zero_approx(light.light_energy), "adapter disables direct sun below horizon")
	adapter.queue_free()
	light.queue_free()
	await process_frame

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("astronomical sun test failed: " + message)
