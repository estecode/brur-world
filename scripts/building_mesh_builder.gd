extends RefCounted
class_name BuildingMeshBuilder

## Builds one batched building mesh from projected OSM footprint records.
##
## Dependencies:
## - Consumes existing OSM-derived building runtime records.
## - Uses tile-local projected coordinates; owns no file I/O, camera state, or streaming policy.

const DEFAULT_HEIGHT_M: float = 9.0
const LEVEL_HEIGHT_M: float = 3.0
const MIN_HEIGHT_M: float = 2.5
const MAX_HEIGHT_M: float = 120.0

static func stable_source_id(record: Dictionary) -> String:
	for key in ["id", "osm_id", "source_id"]:
		if not record.has(key):
			continue
		var source_id := str(record[key])
		if not source_id.is_empty():
			return source_id
	return "xy:%.3f:%.3f" % [float(record.get("x", 0.0)), float(record.get("y", 0.0))]

static func stable_seed(record: Dictionary) -> int:
	return stable_source_id(record).hash()

static func appearance_colors(record: Dictionary) -> Dictionary:
	var seed := absi(stable_seed(record))
	var variation := float(seed % 997) / 996.0
	var wall_value := 0.43 + variation * 0.12
	var roof_value := clampf(wall_value + 0.055 + float((seed / 997) % 5) * 0.008, 0.48, 0.67)
	var wall := Color(wall_value, wall_value + 0.008, wall_value + 0.018, 1.0)
	var roof := Color(roof_value, roof_value + 0.006, roof_value + 0.012, 1.0)
	var base := wall.darkened(0.20)
	return {"wall": wall, "roof": roof, "base": base}

static func height_from_tags(tags: Dictionary) -> float:
	var explicit_height := _numeric_tag(tags.get("height", ""))
	if explicit_height > 0.0:
		return clampf(explicit_height, MIN_HEIGHT_M, MAX_HEIGHT_M)
	var levels := _numeric_tag(tags.get("building:levels", ""))
	if levels > 0.0:
		return clampf(levels * LEVEL_HEIGHT_M, MIN_HEIGHT_M, MAX_HEIGHT_M)
	return DEFAULT_HEIGHT_M

static func build_tile_mesh(records: Array, tile_origin_absolute: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var emitted := 0
	for value in records:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = value
		var tags: Dictionary = record.get("tags", {})
		var height := height_from_tags(tags)
		var colors := appearance_colors(record)
		var polygons: Array = record.get("geometry", [])
		for polygon_value in polygons:
			if typeof(polygon_value) != TYPE_DICTIONARY:
				continue
			var polygon: Dictionary = polygon_value
			var raw_outer: Array = polygon.get("outer", [])
			var outer := _tile_local_ring(raw_outer, tile_origin_absolute)
			if outer.size() < 3:
				continue
			emitted += _add_extruded_polygon(st, outer, height, colors)
	if emitted == 0:
		return null
	st.generate_normals()
	return st.commit()

static func _tile_local_ring(raw: Array, tile_origin_absolute: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point_value in raw:
		if typeof(point_value) != TYPE_ARRAY:
			continue
		var pair: Array = point_value
		if pair.size() < 2:
			continue
		result.append(Vector2(float(pair[0]) - tile_origin_absolute.x, -(float(pair[1]) - tile_origin_absolute.y)))
	if result.size() > 1 and result[0].is_equal_approx(result[result.size() - 1]):
		result.resize(result.size() - 1)
	return result

static func _add_colored_vertex(st: SurfaceTool, vertex: Vector3, color: Color) -> void:
	st.set_color(color)
	st.add_vertex(vertex)

static func _add_extruded_polygon(st: SurfaceTool, outer: PackedVector2Array, height: float, colors: Dictionary) -> int:
	var triangles := Geometry2D.triangulate_polygon(outer)
	if triangles.is_empty():
		return 0
	var roof: Color = colors["roof"]
	var wall: Color = colors["wall"]
	var base: Color = colors["base"]
	var count := 0
	for i in range(0, triangles.size(), 3):
		var a := outer[triangles[i]]
		var b := outer[triangles[i + 1]]
		var c := outer[triangles[i + 2]]
		_add_colored_vertex(st, Vector3(a.x, height, a.y), roof)
		_add_colored_vertex(st, Vector3(b.x, height, b.y), roof)
		_add_colored_vertex(st, Vector3(c.x, height, c.y), roof)
		count += 3
	for i in range(outer.size()):
		var a2 := outer[i]
		var b2 := outer[(i + 1) % outer.size()]
		if a2.is_equal_approx(b2):
			continue
		var a0 := Vector3(a2.x, 0.0, a2.y)
		var b0 := Vector3(b2.x, 0.0, b2.y)
		var a1 := Vector3(a2.x, height, a2.y)
		var b1 := Vector3(b2.x, height, b2.y)
		_add_colored_vertex(st, a0, base)
		_add_colored_vertex(st, b0, base)
		_add_colored_vertex(st, b1, wall)
		_add_colored_vertex(st, a0, base)
		_add_colored_vertex(st, b1, wall)
		_add_colored_vertex(st, a1, wall)
		count += 6
	return count

static func _numeric_tag(value: Variant) -> float:
	var text := str(value).strip_edges().replace(",", ".")
	if text.is_empty():
		return 0.0
	var number := ""
	for character in text:
		if "0123456789.+-".contains(character):
			number += character
		elif not number.is_empty():
			break
	return number.to_float() if not number.is_empty() else 0.0
