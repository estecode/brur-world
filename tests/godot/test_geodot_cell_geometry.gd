extends SceneTree

## Verifies full road-strip polygons, not only centerlines, stay inside presentation cells.
const MeshBuilderScript = preload("res://scripts/geodot_world_mesh_builder.gd")
var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
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
	var left := MeshBuilderScript.clip_polygon_to_cell(full_strip, Vector2(0.0, 0.0), Vector2(10.0, 20.0))
	var right := MeshBuilderScript.clip_polygon_to_cell(full_strip, Vector2(10.0, 0.0), Vector2(20.0, 20.0))
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
	var outside := MeshBuilderScript.clip_polygon_to_cell(
		PackedVector2Array([Vector2(30, 30), Vector2(31, 30), Vector2(31, 31), Vector2(30, 31)]),
		Vector2(0, 0), Vector2(10, 10)
	)
	_assert(outside.is_empty(), "road strip wholly outside a cell emits no cell geometry")
	if _failed:
		quit(1)
		return
	print("geodot cell geometry contracts: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("ASSERT FAILED: " + message)
