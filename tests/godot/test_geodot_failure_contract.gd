extends SceneTree

## Failure-path contracts for the optional GeoDot presentation adapter.
## These run before the native addon is installed in hosted CI.

const SourceScript = preload("res://scripts/geodot_world_source.gd")
const RendererScript = preload("res://scripts/geodot_world_renderer.gd")

var _failed := false

class FakeCoordinates:
	extends RefCounted
	func world_to_absolute(world: Vector3) -> Vector2:
		return Vector2(world.x, -world.z)
	func absolute_to_world(absolute: Vector2, height: float = 0.0) -> Vector3:
		return Vector3(absolute.x, height, -absolute.y)

class FakeCameraRig:
	extends Node
	func get_focus_world() -> Vector3:
		return Vector3.ZERO
	func get_altitude() -> float:
		return 100.0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_missing_geopackage_fails_closed()
	_test_missing_native_addon_fails_closed_when_uninstalled()
	_test_renderer_stays_disabled_after_source_failure()
	if _failed:
		quit(1)
		return
	print("geodot failure contracts: OK")
	quit(0)

func _test_missing_geopackage_fails_closed() -> void:
	var source = SourceScript.new()
	var result: Dictionary = source.open_dataset("/definitely/not/a/brur/geodot-file.gpkg")
	_assert(result.get("ok", false) != true, "missing GeoPackage never reports ready")
	_assert(String(result.get("error", "")).contains("GeoPackage not found"), "missing GeoPackage reports an explicit source error")
	_assert(not source.is_ready(), "missing GeoPackage leaves source unready")

func _test_missing_native_addon_fails_closed_when_uninstalled() -> void:
	if FileAccess.file_exists(SourceScript.GEODOT_EXTENSION_PATH):
		return
	var fixture := "user://geodot-missing-plugin-fixture.gpkg"
	var file := FileAccess.open(fixture, FileAccess.WRITE)
	if file != null:
		file.store_string("not opened because native addon is deliberately absent")
		file.close()
	var source = SourceScript.new()
	var result: Dictionary = source.open_dataset(fixture)
	_assert(result.get("ok", false) != true, "missing native addon never reports ready")
	_assert(String(result.get("error", "")).contains("GeoDot extension is not installed"), "missing native addon reports the exact optional dependency")
	_assert(not source.is_ready(), "missing native addon leaves source unready")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))

func _test_renderer_stays_disabled_after_source_failure() -> void:
	var renderer = RendererScript.new()
	var camera := FakeCameraRig.new()
	get_root().add_child(camera)
	get_root().add_child(renderer)
	var result: Dictionary = renderer.setup(FakeCoordinates.new(), camera, "/definitely/not/a/brur/geodot-file.gpkg")
	_assert(result.get("ok", false) != true, "renderer setup propagates source failure")
	_assert(not renderer.is_ready(), "renderer is not ready after failed source setup")
	_assert(not renderer.is_enabled(), "renderer cannot remain enabled after failed source setup")
	renderer.queue_free()
	camera.queue_free()

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("ASSERT FAILED: " + message)
