extends RefCounted
class_name CityLightModel

## Builds deterministic city-light presentation data from authoritative urban geometry.
##
## Dependencies:
## - Consumes world-space urban triangle positions supplied by the world adapter.
## - Owns only presentation distribution and solar-elevation intensity policy.

const LIGHT_CELL_SIZE_M: float = 1400.0
const DAYLIGHT_OFF_ELEVATION_DEG: float = 0.5
const FULL_NIGHT_ELEVATION_DEG: float = -6.0
const DEFAULT_MAX_POINTS: int = 12000

var _cell_points: Dictionary = {}

func reset_distribution() -> void:
	_cell_points.clear()

func add_urban_triangle(a: Vector3, b: Vector3, c: Vector3) -> void:
	var centroid := (a + b + c) / 3.0
	var cell_x := int(floor(centroid.x / LIGHT_CELL_SIZE_M))
	var cell_z := int(floor(centroid.z / LIGHT_CELL_SIZE_M))
	var key := "%d:%d" % [cell_x, cell_z]
	if _cell_points.has(key):
		return
	_cell_points[key] = Vector3(
		(float(cell_x) + 0.5) * LIGHT_CELL_SIZE_M,
		0.0,
		(float(cell_z) + 0.5) * LIGHT_CELL_SIZE_M
	)

func light_points(max_points: int = DEFAULT_MAX_POINTS) -> Array[Vector3]:
	if max_points <= 0 or _cell_points.is_empty():
		return []
	var keys: Array = _cell_points.keys()
	keys.sort()
	var count := mini(max_points, keys.size())
	var result: Array[Vector3] = []
	result.resize(count)
	if keys.size() <= max_points:
		for index in range(keys.size()):
			result[index] = _cell_points[keys[index]] as Vector3
		return result
	var step := float(keys.size()) / float(count)
	for index in range(count):
		var source_index := mini(keys.size() - 1, int(floor(float(index) * step)))
		result[index] = _cell_points[keys[source_index]] as Vector3
	return result

func source_cell_count() -> int:
	return _cell_points.size()

func night_intensity(solar_elevation_deg: float) -> float:
	if solar_elevation_deg >= DAYLIGHT_OFF_ELEVATION_DEG:
		return 0.0
	if solar_elevation_deg <= FULL_NIGHT_ELEVATION_DEG:
		return 1.0
	return clampf(
		(DAYLIGHT_OFF_ELEVATION_DEG - solar_elevation_deg) /
		(DAYLIGHT_OFF_ELEVATION_DEG - FULL_NIGHT_ELEVATION_DEG),
		0.0,
		1.0
	)
