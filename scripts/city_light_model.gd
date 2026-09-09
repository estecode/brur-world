extends RefCounted
class_name CityLightModel

## Builds deterministic city-light presentation data from authoritative urban geometry and derived runtime POI density.
##
## Dependencies:
## - Consumes world-space urban triangle positions supplied by the world adapter.
## - Consumes compact POI-density samples derived offline from runtime POIs.
## - Owns only presentation distribution and solar-elevation intensity policy.

const LIGHT_CELL_SIZE_M: float = 450.0
const POI_DENSITY_CELL_SIZE_M: float = 2000.0
const DAYLIGHT_OFF_ELEVATION_DEG: float = 0.5
const FULL_NIGHT_ELEVATION_DEG: float = -6.0
const DEFAULT_MAX_POINTS: int = 60000
const BASE_LOCAL_POINTS_PER_CELL: int = 4
const MAX_LOCAL_POINTS_PER_CELL: int = 16
const MAX_GLOW_POINTS_PER_CELL: int = 4

var _cell_points: Dictionary = {}
var _poi_density: Dictionary = {}
var _poi_density_total: int = 0

func reset_distribution() -> void:
	_cell_points.clear()
	_poi_density.clear()
	_poi_density_total = 0

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

func add_poi_density_sample(world_position: Vector3, count: int) -> void:
	if count <= 0:
		return
	var cell_x := int(floor(world_position.x / POI_DENSITY_CELL_SIZE_M))
	var cell_z := int(floor(world_position.z / POI_DENSITY_CELL_SIZE_M))
	var key := "%d:%d" % [cell_x, cell_z]
	_poi_density[key] = int(_poi_density.get(key, 0)) + count
	_poi_density_total += count

func overview_points(max_points: int = DEFAULT_MAX_POINTS) -> Array[Vector3]:
	if max_points <= 0 or _cell_points.is_empty():
		return []
	var result: Array[Vector3] = []
	for center in _weighted_cells():
		var glow_count := _glow_points_for_density(_density_near(center))
		for glow_index in range(glow_count):
			if result.size() >= max_points:
				return result
			result.append(center + _deterministic_glow_offset(center, glow_index))
	return result

func local_light_points(max_points: int = DEFAULT_MAX_POINTS) -> Array[Vector3]:
	if max_points <= 0 or _cell_points.is_empty():
		return []
	var result: Array[Vector3] = []
	for center in _weighted_cells():
		var local_count := _local_points_for_density(_density_near(center))
		for local_index in range(local_count):
			if result.size() >= max_points:
				return result
			result.append(center + _deterministic_local_offset(center, local_index))
	return result

func light_points(max_points: int = DEFAULT_MAX_POINTS) -> Array[Vector3]:
	return overview_points(max_points)

func source_cell_count() -> int:
	return _cell_points.size()

func poi_density_cell_count() -> int:
	return _poi_density.size()

func poi_density_total() -> int:
	return _poi_density_total

func density_weight_at(world_position: Vector3) -> float:
	return _density_weight(_density_near(world_position))

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

func _weighted_cells() -> Array[Vector3]:
	var keys: Array = _cell_points.keys()
	keys.sort_custom(_compare_cells_by_density_then_hash)
	var result: Array[Vector3] = []
	result.resize(keys.size())
	for index in range(keys.size()):
		result[index] = _cell_points[keys[index]] as Vector3
	return result

func _compare_cells_by_density_then_hash(a: Variant, b: Variant) -> bool:
	var a_center := _cell_points[a] as Vector3
	var b_center := _cell_points[b] as Vector3
	var a_density := _density_near(a_center)
	var b_density := _density_near(b_center)
	if a_density != b_density:
		return a_density > b_density
	return _stable_key_hash(String(a)) < _stable_key_hash(String(b))

func _density_near(world_position: Vector3) -> int:
	if _poi_density.is_empty():
		return 0
	var cell_x := int(floor(world_position.x / POI_DENSITY_CELL_SIZE_M))
	var cell_z := int(floor(world_position.z / POI_DENSITY_CELL_SIZE_M))
	var weighted := 0.0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := "%d:%d" % [cell_x + dx, cell_z + dz]
			var count := int(_poi_density.get(key, 0))
			if count <= 0:
				continue
			var influence := 1.0 if dx == 0 and dz == 0 else 0.35
			weighted += float(count) * influence
	return int(round(weighted))

func _density_weight(density: int) -> float:
	if density <= 0:
		return 0.0
	return log(1.0 + float(density)) / log(2.0)

func _glow_points_for_density(density: int) -> int:
	if density <= 0:
		return 1
	return clampi(1 + int(floor(_density_weight(density) / 2.5)), 1, MAX_GLOW_POINTS_PER_CELL)

func _local_points_for_density(density: int) -> int:
	if density <= 0:
		return BASE_LOCAL_POINTS_PER_CELL
	return clampi(BASE_LOCAL_POINTS_PER_CELL + int(round(_density_weight(density) * 1.5)), BASE_LOCAL_POINTS_PER_CELL, MAX_LOCAL_POINTS_PER_CELL)

func _stable_key_hash(key: String) -> int:
	var value: int = 2166136261
	for byte in key.to_utf8_buffer():
		value = int((value ^ int(byte)) * 16777619) & 0x7fffffff
	return value

func _deterministic_glow_offset(center: Vector3, glow_index: int) -> Vector3:
	if glow_index == 0:
		return Vector3.ZERO
	return _deterministic_offset(center, glow_index + 31, LIGHT_CELL_SIZE_M * 0.48)

func _deterministic_local_offset(center: Vector3, local_index: int) -> Vector3:
	return _deterministic_offset(center, local_index, LIGHT_CELL_SIZE_M * 0.82)

func _deterministic_offset(center: Vector3, index: int, spread: float) -> Vector3:
	var cell_x := int(round(center.x / LIGHT_CELL_SIZE_M - 0.5))
	var cell_z := int(round(center.z / LIGHT_CELL_SIZE_M - 0.5))
	var seed := absi(cell_x * 73856093 + cell_z * 19349663 + index * 83492791)
	var x_unit := float(seed % 997) / 996.0
	var z_unit := float((int(seed / 997)) % 991) / 990.0
	return Vector3((x_unit - 0.5) * spread, 0.0, (z_unit - 0.5) * spread)
