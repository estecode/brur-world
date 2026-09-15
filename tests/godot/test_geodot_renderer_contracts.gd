extends SceneTree

## Objective contracts for the GeoDot adapter and batched presentation builders without requiring the native plugin.
## Real GeoPackage/plugin coverage lives in test_geodot_real_data.gd.

const GeoDotWorldSourceScript = preload("res://scripts/geodot_world_source.gd")
const GeoDotWorldMeshBuilderScript = preload("res://scripts/geodot_world_mesh_builder.gd")
const GeoDotWorldRendererScript = preload("res://scripts/geodot_world_renderer.gd")

var _failed := false

class FakePolygonFeature:
	extends RefCounted
	var outer := PackedVector2Array()
	var holes: Array = []
	var attrs: Dictionary = {}
	var feature_id := 1
	func get_outer_vertices() -> PackedVector2Array:
		return outer
	func get_holes() -> Array:
		return holes
	func get_attributes() -> Dictionary:
		return attrs
	func get_id() -> int:
		return feature_id

class FakeCurve:
	extends RefCounted
	var points := PackedVector3Array()
	func get_point_count() -> int:
		return points.size()
	func get_point_position(index: int) -> Vector3:
		return points[index]

class FakeLineFeature:
	extends RefCounted
	var curve := FakeCurve.new()
	var attrs: Dictionary = {}
	var feature_id := 2
	func get_curve3d():
		return curve
	func get_attributes() -> Dictionary:
		return attrs
	func get_id() -> int:
		return feature_id

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_building_adapter()
	_test_real_osm_feature_filtering()
	_test_cell_ownership_is_unique()
	_test_road_adapter()
	_test_road_cell_clipping_is_seam_safe()
	_test_full_road_strip_clipping_is_seam_safe()
	_test_stale_cell_eviction_prefers_replaced_outer_cell()
	_test_far_building_lod_preserves_feature()
	_test_road_mesh_batching()
	if _failed:
		quit(1)
		return
	print("geodot renderer contracts: OK")
	quit(0)

func _test_building_adapter() -> void:
	var feature := FakePolygonFeature.new()
	feature.feature_id = 42
	feature.outer = PackedVector2Array([
		Vector2(1000.0, 2000.0), Vector2(1020.0, 2000.0),
		Vector2(1020.0, 2010.0), Vector2(1000.0, 2010.0),
	])
	feature.holes = [PackedVector2Array([
		Vector2(1005.0, 2003.0), Vector2(1010.0, 2003.0),
		Vector2(1010.0, 2007.0), Vector2(1005.0, 2007.0),
	])]
	feature.attrs = {"building": "yes", "other_tags": "\"building:levels\"=>\"4\",\"name\"=>\"Test\""}
	var record: Dictionary = GeoDotWorldSourceScript.building_record(feature)
	_assert(record.get("id") == "42", "GeoDot building source ID is retained")
	_assert((record.get("geometry", []) as Array).size() == 1, "GeoDot polygon becomes one normalized building geometry")
	var polygon: Dictionary = (record.get("geometry", []) as Array)[0]
	_assert((polygon.get("holes", []) as Array).size() == 1, "GeoDot polygon holes are preserved")
	var tags: Dictionary = record.get("tags", {})
	_assert(tags.get("building:levels") == "4", "GDAL other_tags are normalized for BRUR height policy")
	_assert(is_equal_approx(float(record.get("x", 0.0)), 1010.0), "building center remains in projected metres")

func _test_real_osm_feature_filtering() -> void:
	var landuse := FakePolygonFeature.new()
	landuse.outer = PackedVector2Array([Vector2(0, 0), Vector2(50, 0), Vector2(50, 50), Vector2(0, 50)])
	landuse.attrs = {"landuse": "residential", "building": ""}
	_assert(GeoDotWorldSourceScript.building_record(landuse).is_empty(), "generic multipolygon without building tag is not rendered as a building")
	var building_no := FakePolygonFeature.new()
	building_no.outer = landuse.outer
	building_no.attrs = {"building": "no"}
	_assert(GeoDotWorldSourceScript.building_record(building_no).is_empty(), "building=no is not rendered as a building")
	var railway := FakeLineFeature.new()
	railway.curve.points = PackedVector3Array([Vector3(0, 0, 0), Vector3(100, 0, -100)])
	railway.attrs = {"railway": "rail", "highway": ""}
	_assert(GeoDotWorldSourceScript.road_record(railway).is_empty(), "generic line without highway tag is not rendered as a road")
	var highway_from_other_tags := FakeLineFeature.new()
	highway_from_other_tags.curve.points = railway.curve.points
	highway_from_other_tags.attrs = {"other_tags": "\"highway\"=>\"residential\",\"name\"=>\"Real street\""}
	var road := GeoDotWorldSourceScript.road_record(highway_from_other_tags)
	_assert(not road.is_empty(), "highway promoted only through GDAL other_tags is retained")
	_assert(int(road.get("road_class", -1)) == 5, "residential other_tags road maps to local-road class")

func _test_cell_ownership_is_unique() -> void:
	var left_min := Vector2(0.0, 0.0)
	var left_max := Vector2(10.0, 10.0)
	var right_min := Vector2(10.0, 0.0)
	var right_max := Vector2(20.0, 10.0)
	var boundary_record := {"x": 10.0, "y": 5.0}
	_assert(not GeoDotWorldSourceScript.record_owned_by_cell(boundary_record, left_min, left_max), "building on a shared max edge is not owned by the left cell")
	_assert(GeoDotWorldSourceScript.record_owned_by_cell(boundary_record, right_min, right_max), "building on a shared min edge is owned by exactly the right cell")
	var interior_record := {"x": 9.5, "y": 5.0}
	_assert(GeoDotWorldSourceScript.record_owned_by_cell(interior_record, left_min, left_max), "interior building remains owned by its source cell")
	_assert(not GeoDotWorldSourceScript.record_owned_by_cell(interior_record, right_min, right_max), "interior building cannot be duplicated into an adjacent cell")

func _test_road_adapter() -> void:
	var feature := FakeLineFeature.new()
	feature.feature_id = 99
	feature.attrs = {"highway": "primary"}
	feature.curve.points = PackedVector3Array([
		Vector3(1000.0, 0.0, -2000.0),
		Vector3(1010.0, 0.0, -2010.0),
		Vector3(1020.0, 0.0, -2020.0),
	])
	var record: Dictionary = GeoDotWorldSourceScript.road_record(feature)
	var points: PackedVector2Array = record.get("points", PackedVector2Array())
	_assert(points.size() == 3, "GeoDot line preserves road points")
	_assert(points[1].is_equal_approx(Vector2(1010.0, 2010.0)), "GeoDot Godot-space Z is converted back to projected Y")
	_assert(int(record.get("road_class", -1)) == 2, "primary road maps to BRUR road class")

func _test_road_cell_clipping_is_seam_safe() -> void:
	var a := Vector2(0.0, 5.0)
	var b := Vector2(20.0, 5.0)
	var left := GeoDotWorldMeshBuilderScript.clip_segment_to_cell(a, b, Vector2(0.0, 0.0), Vector2(10.0, 10.0))
	var right := GeoDotWorldMeshBuilderScript.clip_segment_to_cell(a, b, Vector2(10.0, 0.0), Vector2(20.0, 10.0))
	_assert(left.size() == 2 and right.size() == 2, "road crossing a cell boundary produces one bounded segment per cell")
	if left.size() == 2 and right.size() == 2:
		_assert(left[1].x < 10.0, "left cell uses a half-open max edge so the road is not duplicated on the boundary")
		_assert(is_equal_approx(right[0].x, 10.0), "right cell owns the shared boundary from its inclusive min edge")
		_assert(right[0].x - left[1].x <= 0.0011, "cell clipping leaves no visually meaningful road gap")
	var outside := GeoDotWorldMeshBuilderScript.clip_segment_to_cell(Vector2(0.0, 20.0), Vector2(20.0, 20.0), Vector2(0.0, 0.0), Vector2(10.0, 10.0))
	_assert(outside.is_empty(), "road segment outside a cell emits no duplicate geometry")

func _test_full_road_strip_clipping_is_seam_safe() -> void:
	var segment_a := Vector2(2.0, 2.0)
	var segment_b := Vector2(18.0, 18.0)
	var delta := segment_b - segment_a
	var side := Vector2(-delta.y, delta.x).normalized() * 4.0
	var full_strip := PackedVector2Array([
		segment_a - side,
		segment_a + side,
		segment_b + side,
		segment_b - side,
	])
	var left := GeoDotWorldMeshBuilderScript.clip_polygon_to_cell(full_strip, Vector2(0.0, 0.0), Vector2(10.0, 20.0))
	var right := GeoDotWorldMeshBuilderScript.clip_polygon_to_cell(full_strip, Vector2(10.0, 0.0), Vector2(20.0, 20.0))
	_assert(left.size() >= 3 and right.size() >= 3, "diagonal road strip crossing a cell edge survives on both sides")
	var left_max_x := -INF
	var right_min_x := INF
	for point in left:
		left_max_x = maxf(left_max_x, point.x)
		_assert(point.x >= -0.0001 and point.x <= 10.0, "left road strip is fully bounded by its cell")
	for point in right:
		right_min_x = minf(right_min_x, point.x)
		_assert(point.x >= 9.999 and point.x <= 20.0001, "right road strip is fully bounded by its cell")
	_assert(right_min_x - left_max_x <= 0.0011, "adjacent clipped road strips leave no visible seam")
	var outside := GeoDotWorldMeshBuilderScript.clip_polygon_to_cell(
		PackedVector2Array([Vector2(30, 30), Vector2(31, 30), Vector2(31, 31), Vector2(30, 31)]),
		Vector2(0, 0), Vector2(10, 10)
	)
	_assert(outside.is_empty(), "road strip wholly outside a cell emits no cell geometry")

func _test_stale_cell_eviction_prefers_replaced_outer_cell() -> void:
	var active := {"0:0": {}, "1:0": {}, "2:0": {}}
	var desired := {"1:0": 1, "2:0": 1, "3:0": 1}
	var stale := GeoDotWorldRendererScript.choose_stale_eviction_key(active, desired, "3:0")
	_assert(stale == "0:0", "publishing a new desired cell evicts a stale outer cell rather than a still-desired cell")
	var no_stale := GeoDotWorldRendererScript.choose_stale_eviction_key(active, {"0:0": 1, "1:0": 1, "2:0": 1}, "3:0")
	_assert(no_stale.is_empty(), "resident bound never sacrifices a desired cell when no stale slot exists")

func _test_far_building_lod_preserves_feature() -> void:
	var record := {
		"id": "building/1",
		"x": 10.0,
		"y": 10.0,
		"geometry": [{"outer": [[0.0, 0.0], [20.0, 0.0], [18.0, 12.0], [4.0, 16.0]], "holes": []}],
		"tags": {"building": "yes", "building:levels": "3"},
	}
	var mesh := GeoDotWorldMeshBuilderScript.build_buildings([record], Vector2.ZERO, GeoDotWorldMeshBuilderScript.LOD_FAR)
	_assert(mesh != null, "far LOD keeps the building instead of culling it")
	if mesh != null:
		var aabb := mesh.get_aabb()
		_assert(aabb.size.x >= 19.9 and aabb.size.z >= 15.9, "far building proxy preserves massing extent")
		_assert(aabb.size.y >= 8.9, "far building proxy preserves semantic height")

func _test_road_mesh_batching() -> void:
	var roads := [
		{"id": "r1", "points": PackedVector2Array([Vector2(0, 0), Vector2(100, 0)]), "road_class": 2, "tags": {"highway": "primary"}},
		{"id": "r2", "points": PackedVector2Array([Vector2(0, 20), Vector2(100, 20)]), "road_class": 5, "tags": {"highway": "residential"}},
	]
	var mesh := GeoDotWorldMeshBuilderScript.build_roads(roads, Vector2.ZERO, GeoDotWorldMeshBuilderScript.LOD_NEAR)
	_assert(mesh != null, "multiple GeoDot roads batch into one mesh")
	if mesh != null:
		_assert(mesh.get_surface_count() == 1, "road batch uses one surface rather than per-feature nodes")
		_assert(mesh.get_aabb().size.x >= 99.0, "road batch preserves metre-scale length")

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("ASSERT FAILED: " + message)
