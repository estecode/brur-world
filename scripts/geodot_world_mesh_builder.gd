extends RefCounted
class_name GeoDotWorldMeshBuilder

## Builds batched presentation meshes from provider-independent GeoDot adapter records.
## Dependencies: BuildingMeshBuilder for BRUR's existing building height/appearance contract.

const BuildingMeshBuilderScript = preload("res://scripts/building_mesh_builder.gd")
const RoadLodPolicyScript = preload("res://scripts/road_lod_policy.gd")

const LOD_FAR := 0
const LOD_NEAR := 1
const CELL_EDGE_EPSILON_M := 0.001

static func build_buildings(records: Array, cell_origin_absolute: Vector2, lod: int) -> ArrayMesh:
	if lod != LOD_FAR:
		return BuildingMeshBuilderScript.build_tile_mesh(records, cell_origin_absolute)
	var simplified: Array = []
	for value in records:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = value
		var polygons: Array = record.get("geometry", [])
		if polygons.is_empty() or typeof(polygons[0]) != TYPE_DICTIONARY:
			continue
		var raw_outer: Array = (polygons[0] as Dictionary).get("outer", [])
		if raw_outer.size() < 3:
			continue
		var min_x := INF
		var min_y := INF
		var max_x := -INF
		var max_y := -INF
		for point_value in raw_outer:
			if typeof(point_value) != TYPE_ARRAY:
				continue
			var pair: Array = point_value
			if pair.size() < 2:
				continue
			var x := float(pair[0])
			var y := float(pair[1])
			min_x = minf(min_x, x)
			min_y = minf(min_y, y)
			max_x = maxf(max_x, x)
			max_y = maxf(max_y, y)
		if not is_finite(min_x) or max_x - min_x < 0.5 or max_y - min_y < 0.5:
			continue
		var proxy := record.duplicate(true)
		proxy["geometry"] = [{
			"outer": [[min_x, min_y], [max_x, min_y], [max_x, max_y], [min_x, max_y]],
			"holes": [],
		}]
		simplified.append(proxy)
	return BuildingMeshBuilderScript.build_tile_mesh(simplified, cell_origin_absolute)

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
		if lod == LOD_FAR:
			width = maxf(2.0, width * 0.70)
		var color := _road_color(road_class)
		var stride := 2 if lod == LOD_FAR else 1
		var sampled := PackedVector2Array()
		for index in range(0, points.size(), stride):
			sampled.append(points[index])
		if sampled.is_empty() or not sampled[sampled.size() - 1].is_equal_approx(points[points.size() - 1]):
			sampled.append(points[points.size() - 1])
		var has_clip := record.has("clip_min") and record.has("clip_max")
		var clip_min: Vector2 = record.get("clip_min", Vector2.ZERO)
		var clip_max: Vector2 = record.get("clip_max", Vector2.ZERO)
		for index in range(sampled.size() - 1):
			var segment_a := sampled[index]
			var segment_b := sampled[index + 1]
			if has_clip:
				var clipped := clip_segment_to_cell(segment_a, segment_b, clip_min, clip_max)
				if clipped.size() != 2:
					continue
				segment_a = clipped[0]
				segment_b = clipped[1]
			var delta := segment_b - segment_a
			if delta.length_squared() < 0.01:
				continue
			var side := Vector2(-delta.y, delta.x).normalized() * width * 0.5
			var strip := PackedVector2Array([
				segment_a - side,
				segment_a + side,
				segment_b + side,
				segment_b - side,
			])
			if has_clip:
				strip = clip_polygon_to_cell(strip, clip_min, clip_max)
			if strip.size() < 3:
				continue
			for tri_index in range(1, strip.size() - 1):
				for absolute_vertex in [strip[0], strip[tri_index], strip[tri_index + 1]]:
					var absolute_vertex_2d: Vector2 = absolute_vertex
					var local_vertex: Vector2 = absolute_vertex_2d - cell_origin_absolute
					st.set_color(color)
					st.set_normal(Vector3.UP)
					st.add_vertex(Vector3(local_vertex.x, 0.0, -local_vertex.y))
					emitted += 1
	if emitted == 0:
		return null
	return st.commit()

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
