extends SceneTree

## Verifies full road-strip geometry, not only centerlines, stays inside its presentation cell.
const MeshBuilderScript = preload("res://scripts/geodot_world_mesh_builder.gd")
var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var points := PackedVector2Array([Vector2(2.0, 2.0), Vector2(18.0, 18.0)])
	var left_record := {
		"id": "diagonal",
		"points": points,
		"road_class": 2,
		"tags": {"highway": "primary"},
		"clip_min": Vector2(0.0, 0.0),
		"clip_max": Vector2(10.0, 20.0),
	}
	var right_record := left_record.duplicate(true)
	right_record["clip_min"] = Vector2(10.0, 0.0)
	right_record["clip_max"] = Vector2(20.0, 20.0)
	var left_mesh := MeshBuilderScript.build_roads([left_record], Vector2.ZERO, MeshBuilderScript.LOD_NEAR)
	var right_mesh := MeshBuilderScript.build_roads([right_record], Vector2(10.0, 0.0), MeshBuilderScript.LOD_NEAR)
	_assert(left_mesh != null and right_mesh != null, "diagonal road crossing a cell edge renders on both sides")
	if left_mesh != null and right_mesh != null:
		var left_aabb := left_mesh.get_aabb()
		var right_aabb := right_mesh.get_aabb()
		var left_absolute_max_x := left_aabb.position.x + left_aabb.size.x
		var right_absolute_min_x := 10.0 + right_aabb.position.x
		_assert(left_aabb.position.x >= -0.0001, "left road strip never escapes the cell min edge")
		_assert(left_absolute_max_x <= 10.0, "left diagonal road width is clipped at the cell max edge")
		_assert(right_absolute_min_x >= 9.999, "right diagonal road width starts at its owned cell edge")
		_assert(right_aabb.position.x + right_aabb.size.x <= 10.0001, "right road strip remains inside its 10 metre local cell width")
		_assert(right_absolute_min_x - left_absolute_max_x <= 0.0011, "adjacent clipped road strips leave no visible seam")
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
