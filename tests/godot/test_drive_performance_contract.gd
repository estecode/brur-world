extends SceneTree

## Guards Drive against per-frame static scene work and unbounded near-ground building coverage.
##
## Dependencies:
## - camera_controller.gd supplies production Drive framing/render-origin behavior.
## - building_stream_layer.gd and building_lod_policy.gd supply production viewport/LOD selection.
## - drive_render_origin_composition.gd exposes production performance counters only; no test-only behavior.
## - world_coordinates.gd remains the coordinate conversion owner.

const CameraControllerScript = preload("res://scripts/camera_controller.gd")
const BuildingStreamLayerScript = preload("res://scripts/building_stream_layer.gd")
const BuildingLodPolicyScript = preload("res://scripts/building_lod_policy.gd")
const DriveRenderOriginCompositionScript = preload("res://scripts/drive_render_origin_composition.gd")
const GpsRouteDriveRenderAdapterScript = preload("res://scripts/gps_route_drive_render_adapter.gd")
const WorldCoordinatesScript = preload("res://scripts/world_coordinates.gd")

const TEST_WORLD_POSITION := Vector3(52277.0, 0.06, 825907.0)
const SYNTHETIC_BUILDING_LEAVES := 256
const SAME_CELL_FRAMES := 600
const MAX_DRIVE_BUILDING_COVERAGE_CHUNKS := 16

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var rig := Node3D.new()
	rig.name = "CameraRig"
	rig.set_script(CameraControllerScript)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	rig.add_child(camera)
	root.add_child(rig)
	await process_frame

	var target := Node3D.new()
	target.position = TEST_WORLD_POSITION
	root.add_child(target)
	rig.call("set_follow_target", target)
	rig.call("set_drive_mode", true)
	await process_frame

	var drive_altitude := float(rig.call("get_altitude"))
	var drive_lod := BuildingLodPolicyScript.choose_lod(drive_altitude)
	_assert(drive_lod == BuildingLodPolicyScript.LOD_FULL, "Drive uses full building detail")

	var building_stream := BuildingStreamLayerScript.new()
	building_stream.set("_camera_rig", rig)
	building_stream.set("_coordinates", WorldCoordinatesScript.new(Vector2.ZERO, 32000.0))
	var bounds: Dictionary = building_stream.call("_chunk_bounds", drive_lod, 1)
	var coverage := int(building_stream.call("_bounds_chunk_count", bounds))
	print("DRIVE_PERF_BUILDING_COVERAGE chunks=", coverage, " bounds=", bounds, " altitude=", drive_altitude)
	_assert(coverage <= MAX_DRIVE_BUILDING_COVERAGE_CHUNKS, "Drive full-detail building viewport remains tightly bounded")

	var world := Node3D.new()
	var background := MeshInstance3D.new()
	var background_mesh := ArrayMesh.new()
	background_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _triangle_arrays(PackedVector3Array([
		TEST_WORLD_POSITION + Vector3(-20.0, 0.0, -20.0),
		TEST_WORLD_POSITION + Vector3(20.0, 0.0, -20.0),
		TEST_WORLD_POSITION + Vector3(0.0, 0.0, 20.0),
	])))
	background.mesh = background_mesh
	background.material_override = _transparent_material()
	world.add_child(background)

	var buildings := Node3D.new()
	root.add_child(buildings)
	for index in range(SYNTHETIC_BUILDING_LEAVES):
		var leaf := MeshInstance3D.new()
		leaf.position = TEST_WORLD_POSITION + Vector3(float(index % 16) * 20.0, 0.0, float(index / 16) * 20.0)
		leaf.mesh = BoxMesh.new()
		buildings.add_child(leaf)

	var poi := Node3D.new()
	var cloud := Node3D.new()
	var gps_layer := GpsRouteDriveRenderAdapterScript.new()
	gps_layer.player = target
	gps_layer.set("_camera_rig", rig)
	gps_layer.set("_camera", camera)
	gps_layer.route_renderer = Node3D.new()

	var composition := DriveRenderOriginCompositionScript.new()
	composition.set("_camera_rig", rig)
	composition.set("_world", world)
	composition.set("_poi_layer", poi)
	composition.set("_cloud_field", cloud)
	composition.set("_building_layer", buildings)
	composition.set("_gps_route_layer", gps_layer)
	composition.call("_connect_building_branch", buildings)
	composition.call("_sync_render_origin", true)
	var baseline: Dictionary = composition.call("debug_perf_snapshot")
	_assert(int(baseline["background_localizations"]) == 1, "Drive localizes BRM2 exactly once on initial entry")

	for _frame in range(SAME_CELL_FRAMES):
		composition.call("_sync_render_origin", false)
	var same_cell: Dictionary = composition.call("debug_perf_snapshot")
	_assert(int(same_cell["static_syncs"]) == int(baseline["static_syncs"]), "600 same-cell frames perform zero static syncs")
	_assert(int(same_cell["building_leaf_rebases"]) == int(baseline["building_leaf_rebases"]), "600 same-cell frames perform zero building-tree rebases")
	_assert(int(same_cell["background_localizations"]) == int(baseline["background_localizations"]), "600 same-cell frames perform zero background localizations")
	_assert(background.mesh != background_mesh, "Drive keeps localized BRM2 presentation active")

	var stable_background := background.mesh
	for crossing in range(1, 6):
		target.position.x = TEST_WORLD_POSITION.x + float(crossing) * 1100.0
		rig.call("_apply_drive_camera")
		composition.call("_sync_render_origin", false)
	var crossed: Dictionary = composition.call("debug_perf_snapshot")
	_assert(int(crossed["static_syncs"]) == int(baseline["static_syncs"]) + 5, "five render-cell crossings cause exactly five static syncs")
	_assert(int(crossed["background_localizations"]) == 1, "render-cell crossings never relocalize/copy BRM2")
	_assert(background.mesh == stable_background, "render-cell crossings retain exact BRM2 resource")

	print("DRIVE_PERF_COUNTERS baseline=", baseline, " same_cell=", same_cell, " crossed=", crossed)
	composition.free()
	gps_layer.route_renderer.free()
	gps_layer.free()
	world.free()
	buildings.free()
	poi.free()
	cloud.free()
	building_stream.free()
	target.free()
	rig.free()
	print("godot drive-performance-contract tests: OK")
	quit(0)

func _triangle_arrays(vertices: PackedVector3Array) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	return arrays

func _transparent_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return material

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("drive-performance-contract test failed: " + message)
	quit(1)
