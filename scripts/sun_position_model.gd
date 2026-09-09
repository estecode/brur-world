extends RefCounted
class_name SunPositionModel

## Computes deterministic solar position and daylight facts from civil time and geographic coordinates.
## Dependencies: Godot math/value types only; does not depend on SceneTree, rendering, world data, networking, or WorldClock.

const SUNRISE_ZENITH_DEG := 90.833
const MIN_TIMEZONE_OFFSET_HOURS := -14.0
const MAX_TIMEZONE_OFFSET_HOURS := 14.0

func calculate(time_snapshot: Dictionary, latitude_deg: float, longitude_deg: float) -> Dictionary:
	if not _is_valid_input(time_snapshot, latitude_deg, longitude_deg):
		return {"valid": false}

	var year := int(time_snapshot["year"])
	var month := int(time_snapshot["month"])
	var day := int(time_snapshot["day"])
	var hour := int(time_snapshot["hour"])
	var minute := int(time_snapshot.get("minute", 0))
	var second := int(time_snapshot.get("second", 0))
	var utc_offset_hours := float(time_snapshot.get("utc_offset_hours", 0.0))
	var day_of_year := _day_of_year(year, month, day)
	var days_in_year := 366.0 if _is_leap_year(year) else 365.0
	var decimal_hour := float(hour) + float(minute) / 60.0 + float(second) / 3600.0

	# NOAA fractional-year approximation for equation of time and solar declination.
	var gamma := TAU / days_in_year * (float(day_of_year - 1) + (decimal_hour - 12.0) / 24.0)
	var equation_of_time_minutes := 229.18 * (
		0.000075
		+ 0.001868 * cos(gamma)
		- 0.032077 * sin(gamma)
		- 0.014615 * cos(2.0 * gamma)
		- 0.040849 * sin(2.0 * gamma)
	)
	var declination_rad := (
		0.006918
		- 0.399912 * cos(gamma)
		+ 0.070257 * sin(gamma)
		- 0.006758 * cos(2.0 * gamma)
		+ 0.000907 * sin(2.0 * gamma)
		- 0.002697 * cos(3.0 * gamma)
		+ 0.00148 * sin(3.0 * gamma)
	)

	var local_minutes := decimal_hour * 60.0
	var time_offset_minutes := equation_of_time_minutes + 4.0 * longitude_deg - 60.0 * utc_offset_hours
	var true_solar_minutes := fposmod(local_minutes + time_offset_minutes, 1440.0)
	var hour_angle_deg := true_solar_minutes / 4.0 - 180.0
	if hour_angle_deg < -180.0:
		hour_angle_deg += 360.0
	var hour_angle_rad := deg_to_rad(hour_angle_deg)
	var latitude_rad := deg_to_rad(latitude_deg)

	var cos_zenith := (
		sin(latitude_rad) * sin(declination_rad)
		+ cos(latitude_rad) * cos(declination_rad) * cos(hour_angle_rad)
	)
	cos_zenith = clampf(cos_zenith, -1.0, 1.0)
	var zenith_deg := rad_to_deg(acos(cos_zenith))
	var elevation_deg := 90.0 - zenith_deg
	var azimuth_deg := rad_to_deg(atan2(
		sin(hour_angle_rad),
		cos(hour_angle_rad) * sin(latitude_rad) - tan(declination_rad) * cos(latitude_rad)
	)) + 180.0
	azimuth_deg = fposmod(azimuth_deg, 360.0)

	var daylight := _daylight_state(latitude_rad, declination_rad, equation_of_time_minutes, longitude_deg, utc_offset_hours)
	return {
		"valid": true,
		"azimuth_deg": azimuth_deg,
		"elevation_deg": elevation_deg,
		"zenith_deg": zenith_deg,
		"sun_above_horizon": elevation_deg > 0.0,
		"solar_declination_deg": rad_to_deg(declination_rad),
		"equation_of_time_minutes": equation_of_time_minutes,
		"true_solar_minutes": true_solar_minutes,
		"daylight_minutes": daylight["daylight_minutes"],
		"sunrise_minutes_local": daylight["sunrise_minutes_local"],
		"sunset_minutes_local": daylight["sunset_minutes_local"],
		"polar_day": daylight["polar_day"],
		"polar_night": daylight["polar_night"],
	}

func _daylight_state(latitude_rad: float, declination_rad: float, equation_of_time_minutes: float, longitude_deg: float, utc_offset_hours: float) -> Dictionary:
	var denominator := cos(latitude_rad) * cos(declination_rad)
	var solar_noon_minutes := 720.0 - 4.0 * longitude_deg - equation_of_time_minutes + 60.0 * utc_offset_hours
	if absf(denominator) < 0.0000001:
		var elevation_at_pole := rad_to_deg(asin(clampf(sin(latitude_rad) * sin(declination_rad), -1.0, 1.0)))
		var pole_day := elevation_at_pole > -0.833
		return {
			"daylight_minutes": 1440.0 if pole_day else 0.0,
			"sunrise_minutes_local": -1.0,
			"sunset_minutes_local": -1.0,
			"polar_day": pole_day,
			"polar_night": not pole_day,
		}

	var cos_hour_angle := (
		cos(deg_to_rad(SUNRISE_ZENITH_DEG)) / denominator
		- tan(latitude_rad) * tan(declination_rad)
	)
	if cos_hour_angle < -1.0:
		return {
			"daylight_minutes": 1440.0,
			"sunrise_minutes_local": -1.0,
			"sunset_minutes_local": -1.0,
			"polar_day": true,
			"polar_night": false,
		}
	if cos_hour_angle > 1.0:
		return {
			"daylight_minutes": 0.0,
			"sunrise_minutes_local": -1.0,
			"sunset_minutes_local": -1.0,
			"polar_day": false,
			"polar_night": true,
		}

	var hour_angle_deg := rad_to_deg(acos(clampf(cos_hour_angle, -1.0, 1.0)))
	var daylight_minutes := 8.0 * hour_angle_deg
	return {
		"daylight_minutes": daylight_minutes,
		"sunrise_minutes_local": fposmod(solar_noon_minutes - 4.0 * hour_angle_deg, 1440.0),
		"sunset_minutes_local": fposmod(solar_noon_minutes + 4.0 * hour_angle_deg, 1440.0),
		"polar_day": false,
		"polar_night": false,
	}

func _is_valid_input(time_snapshot: Dictionary, latitude_deg: float, longitude_deg: float) -> bool:
	if latitude_deg < -90.0 or latitude_deg > 90.0 or longitude_deg < -180.0 or longitude_deg > 180.0:
		return false
	for key in ["year", "month", "day", "hour"]:
		if not time_snapshot.has(key):
			return false
	var year := int(time_snapshot["year"])
	var month := int(time_snapshot["month"])
	var day := int(time_snapshot["day"])
	var hour := int(time_snapshot["hour"])
	var minute := int(time_snapshot.get("minute", 0))
	var second := int(time_snapshot.get("second", 0))
	var utc_offset_hours := float(time_snapshot.get("utc_offset_hours", 0.0))
	if year < 1 or year > 9999 or month < 1 or month > 12 or hour < 0 or hour > 23:
		return false
	if minute < 0 or minute > 59 or second < 0 or second > 59:
		return false
	if utc_offset_hours < MIN_TIMEZONE_OFFSET_HOURS or utc_offset_hours > MAX_TIMEZONE_OFFSET_HOURS:
		return false
	return day >= 1 and day <= _days_in_month(year, month)

func _day_of_year(year: int, month: int, day: int) -> int:
	var total := day
	for current_month in range(1, month):
		total += _days_in_month(year, current_month)
	return total

func _days_in_month(year: int, month: int) -> int:
	match month:
		2:
			return 29 if _is_leap_year(year) else 28
		4, 6, 9, 11:
			return 30
		_:
			return 31

func _is_leap_year(year: int) -> bool:
	return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)
