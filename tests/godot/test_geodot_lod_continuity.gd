extends SceneTree

const MeshBuilderScript = preload("res://scripts/geodot_world_mesh_builder.gd")
var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var footprint := [[0.0, 0.0], [12.0, 0.0], [12.0, 4.0], [8.0, 4.0], [8.0, 10.0], [0.0, 10.0]]
	var record := {"geometry": [{"outer": footprint, "holes": []}], "height": 12.0, "building": "yes"}
	var far_mesh: ArrayMesh = MeshBuilderScript.build_buildings([record], Vector2.ZERO, MeshBuilderScript.LOD_FAR)
	var near_mesh: ArrayMesh = MeshBuilderScript.build_buildings([record], Vector2.ZERO, MeshBuilderScript.LOD_NEAR)
	_assert(far_mesh != null and near_mesh != null, "both building LODs produce geometry")
	if far_mesh != null and near_mesh != null:
		var far_aabb := far_mesh.get_aabb()
		var near_aabb := near_mesh.get_aabb()
		_assert(far_aabb.position.distance_to(near_aabb.position) <= 0.01, "LOD keeps building origin stable")
		_assert(far_aabb.size.distance_to(near_aabb.size) <= 0.01, "LOD keeps building footprint/height bounds stable")
	var road := {"points": PackedVector2Array([Vector2(0, 0), Vector2(20, 0), Vector2(30, 10)]), "road_class": 1}
	var far_road: ArrayMesh = MeshBuilderScript.build_roads([road], Vector2.ZERO, MeshBuilderScript.LOD_FAR)
	var near_road: ArrayMesh = MeshBuilderScript.build_roads([road], Vector2.ZERO, MeshBuilderScript.LOD_NEAR)
	_assert(far_road != null and near_road != null, "both road LODs produce geometry")
	if far_road != null and near_road != null:
		_assert(absf(far_road.get_aabb().size.z - near_road.get_aabb().size.z) <= 0.01, "LOD does not change road physical width")
	if _failed:
		quit(1)
		return
	print("geodot LOD continuity contracts: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("ASSERT FAILED: " + message)
