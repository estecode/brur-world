extends SceneTree

## Objective contracts for the GeoDot adapter and batched presentation builders without requiring the native plugin.
## Real GeoPackage/plugin coverage lives in test_geodot_real_data.gd.

const GeoDotWorldSourceScript = preload("res://scripts/geodot_world_source.gd")
const GeoDotWorldMeshBuilderScript = preload("res://scripts/geodot_world_mesh_builder.gd")

var _failed := false

class FakePolygonFeature:
	extends RefCounted
	var outer := PackedVector2Array()
	var attrs: Dictionary = {}
	var feature_id := 1
	func get_outer_vertices() -> PackedVector2Array:
		return outer
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
	_test_road_adapter()
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
	feature.attrs = {"building": "yes", "other_tags": "\"building:levels\"=>\"4\",\"name\"=>\"Test\""}
	var record: Dictionary = GeoDotWorldSourceScript.building_record(feature)
	_assert(record.get("id") == "42", "GeoDot building source ID is retained")
	_assert((record.get("geometry", []) as Array).size() == 1, "GeoDot polygon becomes one normalized building geometry")
	var tags: Dictionary = record.get("tags", {})
	_assert(tags.get("building:levels") == "4", "GDAL other_tags are normalized for BRUR height policy")
	_assert(is_equal_approx(float(record.get("x", 0.0)), 1010.0), "building center remains in projected metres")

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
