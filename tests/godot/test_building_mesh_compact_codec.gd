extends SceneTree

## Verifies the production building codec decodes the compact BMC3 Windows-pack format.
## Dependencies: production BuildingMeshChunkCodec only; fixture bytes are deterministic.

const Codec = preload("res://scripts/building_mesh_chunk_codec.gd")
const BMC3_FIXTURE_BASE64 := "Qk1DMwMAAAAGAAAAAAD2QgAA5MMGAAAAAAAAAIyOkP9aXF//bnBz/wAAWgAAAAAABGQAWgAAAAAABAAAWgBkAAAABAAAAAAAAIEAAQAAAABkAIEAAQAAWgBkAIEAAg=="

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func _initialize() -> void:
	var path := "user://compact-building-codec-test.bmc"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("could not create compact BMC3 fixture")
		return
	file.store_buffer(Marshalls.base64_to_raw(BMC3_FIXTURE_BASE64))
	file.close()

	var decoded := Codec.decode_file(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if decoded.get("ok", false) != true:
		_fail("BMC3 decode failed: %s" % String(decoded.get("error", "unknown")))
		return
	if int(decoded.get("format", 0)) != 3 or int(decoded.get("vertices", 0)) != 6:
		_fail("BMC3 format/vertex count mismatch")
		return
	var positions: PackedVector3Array = decoded.get("positions", PackedVector3Array())
	var normals: PackedVector3Array = decoded.get("normals", PackedVector3Array())
	var colors: PackedColorArray = decoded.get("colors", PackedColorArray())
	if positions.size() != 6 or normals.size() != 6 or colors.size() != 6:
		_fail("BMC3 decoded array sizes mismatch")
		return
	if positions[0].distance_to(Vector3(123.0, 9.0, -456.0)) > 0.001:
		_fail("BMC3 compact position decode mismatch")
		return
	if normals[0].distance_to(Vector3.UP) > 0.001:
		_fail("BMC3 roof normal decode mismatch")
		return
	if normals[3].distance_to(Vector3(-1.0, 0.0, 0.0)) > 0.001:
		_fail("BMC3 wall normal decode mismatch")
		return
	var expected := Color8(140, 142, 144, 255)
	if colors[0] != expected:
		_fail("BMC3 palette color decode mismatch")
		return
	print("BUILDING_COMPACT_CODEC=OK vertices=6 format=3")
	quit(0)
