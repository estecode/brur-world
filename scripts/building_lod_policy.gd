extends RefCounted
class_name BuildingLodPolicy

## Selects deterministic building detail from camera altitude and OSM-derived footprint size.
##
## Dependencies:
## - Consumes existing building runtime records only.
## - Has no SceneTree, rendering, file-I/O, or world-coordinate dependencies.

const LOD_COARSE := 0
const LOD_LARGE := 1
const LOD_MEDIUM := 2
const LOD_FULL := 3

const COARSE_ALTITUDE_M := 8000.0
const LARGE_ALTITUDE_M := 3500.0
const MEDIUM_ALTITUDE_M := 1200.0

const COARSE_MIN_AREA_M2 := 3500.0
const LARGE_MIN_AREA_M2 := 1200.0
const MEDIUM_MIN_AREA_M2 := 300.0

static func choose_lod(altitude_m: float) -> int:
	if altitude_m >= COARSE_ALTITUDE_M:
		return LOD_COARSE
	if altitude_m >= LARGE_ALTITUDE_M:
		return LOD_LARGE
	if altitude_m >= MEDIUM_ALTITUDE_M:
		return LOD_MEDIUM
	return LOD_FULL

static func minimum_footprint_area_m2(lod: int) -> float:
	match lod:
		LOD_COARSE:
			return COARSE_MIN_AREA_M2
		LOD_LARGE:
			return LARGE_MIN_AREA_M2
		LOD_MEDIUM:
			return MEDIUM_MIN_AREA_M2
		_:
			return 0.0

static func record_visible(record: Dictionary, lod: int) -> bool:
	return footprint_area_m2(record) >= minimum_footprint_area_m2(lod)

static func filter_records(records: Array, lod: int) -> Array:
	if lod >= LOD_FULL:
		return records
	var result: Array = []
	for value in records:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = value
		if record_visible(record, lod):
			result.append(record)
	return result

static func footprint_area_m2(record: Dictionary) -> float:
	var total := 0.0
	for polygon_value in record.get("geometry", []):
		if typeof(polygon_value) != TYPE_DICTIONARY:
			continue
		var polygon: Dictionary = polygon_value
		total += absf(_ring_signed_area(polygon.get("outer", [])))
		for hole_value in polygon.get("holes", []):
			if typeof(hole_value) == TYPE_ARRAY:
				total -= absf(_ring_signed_area(hole_value))
	return maxf(0.0, total)

static func _ring_signed_area(raw_ring: Array) -> float:
	if raw_ring.size() < 3:
		return 0.0
	var area := 0.0
	for index in range(raw_ring.size()):
		var a_value: Variant = raw_ring[index]
		var b_value: Variant = raw_ring[(index + 1) % raw_ring.size()]
		if typeof(a_value) != TYPE_ARRAY or typeof(b_value) != TYPE_ARRAY:
			continue
		var a: Array = a_value
		var b: Array = b_value
		if a.size() < 2 or b.size() < 2:
			continue
		area += float(a[0]) * float(b[1]) - float(b[0]) * float(a[1])
	return area * 0.5
