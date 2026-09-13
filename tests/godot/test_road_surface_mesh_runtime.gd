extends SceneTree

## Verifies production Main consumes prebuilt BRS1 triangles without rebuilding segment quads.
## Dependencies: production Main road tile decoder and a temporary synthetic BRS1 fixture only.

const MainScript = preload("res://scripts/main.gd")
const MAGIC := "BRS1"

var failures: int = 0

func _init() -> void:
	var path := "user://road_surface_runtime_test.brmesh"
	_write_fixture(path)
	var main = MainScript.new()
	var mesh: ArrayMesh = main.call("_build_tile_mesh", path, 2) as ArrayMesh
	_assert(mesh != null, "BRS1 fixture decodes into an ArrayMesh")
	if mesh != null:
		_assert(mesh.get_surface_count() == 1, "BRS1 tile creates one GPU-facing surface")
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		_assert(vertices.size() == 6, "two prebuilt triangles remain exactly six vertices")
		_assert(colors.size() == 6, "class colors are stored per prebuilt vertex")
		_assert(is_equal_approx(vertices[0].y, 0.0), "ground-grade triangle stays at road base height")
		_assert(is_equal_approx(vertices[3].y, 0.25), "grade-separated triangle receives deterministic physical grade offset")
		_assert(vertices[0].x == 1.0 and vertices[0].z == -2.0, "tile-local BRS1 coordinates map directly to GPU-local X/Z")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	main.free()
	if failures == 0:
		print("ROAD_SURFACE_MESH_RUNTIME_TEST=PASS")
		quit(0)
	else:
		quit(1)

func _write_fixture(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	_assert(file != null, "BRS1 fixture is writable")
	if file == null:
		return
	file.store_buffer(MAGIC.to_ascii_buffer())
	file.store_32(2)
	_write_triangle(file, 0, 0, Vector2(1.0, 2.0), Vector2(5.0, 2.0), Vector2(1.0, 6.0))
	_write_triangle(file, 5, 1, Vector2(10.0, 12.0), Vector2(14.0, 12.0), Vector2(10.0, 16.0))
	file.close()

func _write_triangle(file: FileAccess, road_class: int, grade: int, a: Vector2, b: Vector2, c: Vector2) -> void:
	file.store_8(road_class)
	file.store_8(grade & 0xff)
	for point in [a, b, c]:
		file.store_float(point.x)
		file.store_float(point.y)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
