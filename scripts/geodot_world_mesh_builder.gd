extends RefCounted
class_name GeoDotWorldMeshBuilder

## Builds batched presentation meshes from provider-independent GeoDot adapter records.
## LOD may remove vertices/detail, but never replaces a building with a different
## footprint or changes road width. Spatial identity stays stable across tiers.

const BuildingMeshBuilderScript = preload("res://scripts/building_mesh_builder.gd")
const RoadLodPolicyScript = preload("res://scripts/road_lod_policy.gd")

const LOD_FAR := 0
const LOD_NEAR := 1
const CELL_EDGE_EPSILON_M := 0.001
const FAR_SIMPLIFY_EPSILON_M := 1.5

static func build_buildings(records: Array, cell_origin_absolute: Vector2, lod: int) -> ArrayMesh:
	if lod != LOD_FAR:
		return BuildingMeshBuilderScript.build_tile_mesh(records, cell_origin_absolute)
	var simplified: Array = []
	for value in records:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = value
		var polygons: Array = record.get("geometry", [])
		var stable_polygons: Array = []
		for polygon_value in polygons:
			if typeof(polygon_value) != TYPE_DICTIONARY:
				continue
			var polygon: Dictionary = polygon_value
			var outer := _simplify_ring(polygon.get("outer", []), FAR_SIMPLIFY_EPSILON_M)
			if outer.size() < 3:
				outer = polygon.get("outer", []).duplicate(true)
			if outer.size() < 3:
				continue
			stable_polygons.append({"outer": outer, "holes": []})
		if stable_polygons.is_empty():
			continue
		var proxy := record.duplicate(true)
		proxy["geometry"] = stable_polygons
		simplified.append(proxy)
	return BuildingMeshBuilderScript.build_tile_mesh(simplified, cell_origin_absolute)

static func _simplify_ring(raw: Array, epsilon_m: float) -> Array:
	if raw.size() <= 4:
		return raw.duplicate(true)
	var points: Array[Vector2] = []
	for value in raw:
		if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 2:
			points.append(Vector2(float(value[0]), float(value[1])))
	if points.size() <= 4:
		return raw.duplicate(true)
	var result: Array = []
	for index in range(points.size()):
		var previous := points[(index - 1 + points.size()) % points.size()]
		var current := points[index]
		var next := points[(index + 1) % points.size()]
		var baseline := next - previous
		var distance := current.distance_to(previous)
		if baseline.length_squared() > 0.0001:
			distance = absf(baseline.cross(current - previous)) / baseline.length()
		if distance >= epsilon_m or current.distance_to(previous) >= epsilon_m * 3.0:
			result.append([current.x, current.y])
	return result if result.size() >= 3 else raw.duplicate(true)

static func build_roads(records: Array, cell_origin_absolute: Vector2, lod: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var emitted := 0
	for value in records:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = value
		var points: PackedVector2Array = record.get("points", PackedVector2Array())
		if points.size() < 2:
			continue
		var road_class := int(record.get("road_class", 5))
		var width := RoadLodPolicyScript.road_width_m(road_class)
		var color := _road_color(road_class)
		var sampled := points if lod == LOD_NEAR else _simplify_polyline(points, 2.0)
		var has_clip := record.has("clip_min") and record.has("clip_max")
		var clip_min: Vector2 = record.get("clip_min", Vector2.ZERO)
		var clip_max: Vector2 = record.get("clip_max", Vector2.ZERO)
		emitted += _emit_polyline(st, sampled, width, color, cell_origin_absolute, clip_min, clip_max, has_clip)
	if emitted == 0:
		return null
	st.index()
	return st.commit()

static func _emit_polyline(st: SurfaceTool, points: PackedVector2Array, width: float, color: Color, origin: Vector2, cell_min: Vector2, cell_max: Vector2, has_clip: bool) -> int:
	var count := points.size()
	if count < 2:
		return 0
	var half := width * 0.5
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for index in range(count):
		var tangent: Vector2
		if index == 0:
			tangent = (points[1] - points[0]).normalized()
		elif index == count - 1:
			tangent = (points[index] - points[index - 1]).normalized()
		else:
			var incoming := (points[index] - points[index - 1]).normalized()
			var outgoing := (points[index + 1] - points[index]).normalized()
			tangent = (incoming + outgoing).normalized()
			if tangent.length_squared() < 0.01:
				tangent = outgoing
		var normal := Vector2(-tangent.y, tangent.x)
		var scale := half
		if index > 0 and index < count - 1:
			var incoming_normal := Vector2(-(points[index] - points[index - 1]).normalized().y, (points[index] - points[index - 1]).normalized().x)
			var denom := maxf(0.35, absf(normal.dot(incoming_normal)))
			scale = minf(half / denom, half * 2.0)
		left.append(points[index] + normal * scale)
		right.append(points[index] - normal * scale)
	var emitted := 0
	for index in range(count - 1):
		var strip := PackedVector2Array([left[index], right[index], right[index + 1], left[index + 1]])
		if has_clip:
			strip = clip_polygon_to_cell(strip, cell_min, cell_max)
		if strip.size() < 3:
			continue
		var local_points := PackedVector2Array()
		for point in strip:
			local_points.append(point - origin)
		var triangles := Geometry2D.triangulate_polygon(local_points)
		if triangles.is_empty():
			continue
		for triangle_index in range(0, triangles.size(), 3):
			for vertex_index in [triangles[triangle_index], triangles[triangle_index + 1], triangles[triangle_index + 2]]:
				var local: Vector2 = local_points[vertex_index]
				st.set_color(color)
				st.set_normal(Vector3.UP)
				st.add_vertex(Vector3(local.x, 0.0, -local.y))
			emitted += triangles.size()
	return emitted

static func _simplify_polyline(points: PackedVector2Array, epsilon_m: float) -> PackedVector2Array:
	if points.size() <= 2:
		return points
	var result := PackedVector2Array([points[0]])
	for index in range(1, points.size() - 1):
		var previous := result[result.size() - 1]
		var current := points[index]
		var next := points[index + 1]
		var baseline := next - previous
		var distance := current.distance_to(previous)
		if baseline.length_squared() > 0.0001:
			distance = absf(baseline.cross(current - previous)) / baseline.length()
		if distance >= epsilon_m:
			result.append(current)
	result.append(points[points.size() - 1])
	return result

static func clip_segment_to_cell(a: Vector2, b: Vector2, cell_min: Vector2, cell_max: Vector2) -> PackedVector2Array:
	var effective_max := _effective_cell_max(cell_min, cell_max)
	var delta := b - a
	var p := PackedFloat64Array([-delta.x, delta.x, -delta.y, delta.y])
	var q := PackedFloat64Array([a.x - cell_min.x, effective_max.x - a.x, a.y - cell_min.y, effective_max.y - a.y])
	var enter := 0.0
	var leave := 1.0
	for index in range(4):
		var pi := float(p[index])
		var qi := float(q[index])
		if is_zero_approx(pi):
			if qi < 0.0:
				return PackedVector2Array()
			continue
		var ratio := qi / pi
		if pi < 0.0:
			enter = maxf(enter, ratio)
		else:
			leave = minf(leave, ratio)
		if enter > leave:
			return PackedVector2Array()
	return PackedVector2Array([a + delta * enter, a + delta * leave])

static func clip_polygon_to_cell(polygon: PackedVector2Array, cell_min: Vector2, cell_max: Vector2) -> PackedVector2Array:
	var effective_max := _effective_cell_max(cell_min, cell_max)
	var result := polygon
	result = _clip_polygon_axis(result, 0, cell_min.x, true)
	result = _clip_polygon_axis(result, 0, effective_max.x, false)
	result = _clip_polygon_axis(result, 1, cell_min.y, true)
	result = _clip_polygon_axis(result, 1, effective_max.y, false)
	return result

static func _clip_polygon_axis(polygon: PackedVector2Array, axis: int, boundary: float, keep_greater: bool) -> PackedVector2Array:
	var output := PackedVector2Array()
	if polygon.is_empty():
		return output
	var previous := polygon[polygon.size() - 1]
	var previous_coordinate := previous.x if axis == 0 else previous.y
	var previous_inside := previous_coordinate >= boundary if keep_greater else previous_coordinate <= boundary
	for current in polygon:
		var current_coordinate := current.x if axis == 0 else current.y
		var current_inside := current_coordinate >= boundary if keep_greater else current_coordinate <= boundary
		if current_inside != previous_inside:
			var denominator := current_coordinate - previous_coordinate
			if not is_zero_approx(denominator):
				var ratio := (boundary - previous_coordinate) / denominator
				output.append(previous.lerp(current, ratio))
		if current_inside:
			output.append(current)
		previous = current
		previous_coordinate = current_coordinate
		previous_inside = current_inside
	return output

static func _effective_cell_max(cell_min: Vector2, cell_max: Vector2) -> Vector2:
	return Vector2(maxf(cell_min.x, cell_max.x - CELL_EDGE_EPSILON_M), maxf(cell_min.y, cell_max.y - CELL_EDGE_EPSILON_M))

static func _road_color(road_class: int) -> Color:
	if road_class <= 0:
		return Color(1.0, 0.58, 0.20)
	if road_class <= 2:
		return Color(1.0, 0.78, 0.36)
	if road_class <= 4:
		return Color(0.92, 0.88, 0.72)
	return Color(0.62, 0.66, 0.64)
