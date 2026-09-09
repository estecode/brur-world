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
const LOCAL_POINTS_PER_CELL: int = 3

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

func overview_points(max_points: int = DEFAULT_MAX_POINTS) -> Array[Vector3]:
	return _sample_cells(max_points)

func local_light_points(max_points: int = DEFAULT_MAX_POINTS) -> Array[Vector3]:
	if max_points <= 0 or _cell_points.is_empty():
		return []
	var cells := _sample_cells(maxi(1, int(ceil(float(max_points) / float(LOCAL_POINTS_PER_CELL)))))
	var result: Array[Vector3] = []
	for center in cells:
		for local_index in range(LOCAL_POINTS_PER_CELL):
			if result.size() >= max_points:
				return result
			result.append(center + _deterministic_local_offset(center, local_index))
	return result

func light_points(max_points: int = DEFAULT_MAX_POINTS) -> Array[Vector3]:
	return overview_points(max_points)

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

func _sample_cells(max_points: int) -> Array[Vector3]:
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

func _deterministic_local_offset(center: Vector3, local_index: int) -> Vector3:
	var cell_x := int(round(center.x / LIGHT_CELL_SIZE_M - 0.5))
	var cell_z := int(round(center.z / LIGHT_CELL_SIZE_M - 0.5))
	var seed := absi(cell_x * 73856093 + cell_z * 19349663 + local_index * 83492791)
	var x_unit := float(seed % 997) / 996.0
	var z_unit := float((seed / 997) % 991) / 990.0
	var spread := LIGHT_CELL_SIZE_M * 0.58
	return Vector3((x_unit - 0.5) * spread, 0.0, (z_unit - 0.5) * spread)
