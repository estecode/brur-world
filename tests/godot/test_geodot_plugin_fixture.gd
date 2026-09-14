extends SceneTree

## Native GeoDot fixture check used by hosted CI. Requires BRUR_GEODOT_GPKG.
const SourceScript = preload("res://scripts/geodot_world_source.gd")
const MeshBuilderScript = preload("res://scripts/geodot_world_mesh_builder.gd")
var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var path := OS.get_environment("BRUR_GEODOT_GPKG")
	_assert(not path.is_empty(), "fixture GeoPackage path configured")
	var source = SourceScript.new()
	var opened: Dictionary = source.open_dataset(path)
	_assert(opened.get("ok", false) == true, "native GeoDot opens fixture GeoPackage")
	_assert(int(opened.get("epsg", 0)) == 3006, "fixture keeps EPSG:3006")
	if opened.get("ok", false) != true:
		print(opened)
		quit(1)
		return
	var result: Dictionary = source.query_cell(Vector2(0.0, 2000.0), 2000.0, 100, 100)
	_assert(int(result.get("building_features", 0)) == 1, "spatial query finds fixture building")
	_assert(int(result.get("road_features", 0)) == 1, "spatial query finds fixture road")
	var bmesh := MeshBuilderScript.build_buildings(result.get("buildings", []), Vector2.ZERO, MeshBuilderScript.LOD_NEAR)
	var rmesh := MeshBuilderScript.build_roads(result.get("roads", []), Vector2.ZERO, MeshBuilderScript.LOD_NEAR)
	_assert(bmesh != null and bmesh.get_surface_count() == 1, "fixture building renders as batched mesh")
	_assert(rmesh != null and rmesh.get_surface_count() == 1, "fixture road renders as batched mesh")
	if _failed:
		quit(1)
		return
	print("geodot native fixture test: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("ASSERT FAILED: " + message)
