extends RefCounted
class_name BuildingMeshChunkCodec

## Decodes and combines prebuilt binary building render chunks off the presentation path.
##
## Dependencies:
## - Consumes only the BUILDING_MESH_LOD BMC1 binary format from the offline builder.
## - Owns no camera, SceneTree, material, or world-streaming policy.

const MAGIC := "BMC1"
const FORMAT_VERSION := 1
const HEADER_BYTES := 12
const VERTEX_BYTES := 28

static func decode_file(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < HEADER_BYTES:
		return {"ok": false, "error": "short-header", "bytes": bytes.size()}
	var magic := bytes.slice(0, 4).get_string_from_ascii()
	if magic != MAGIC:
		return {"ok": false, "error": "bad-magic", "bytes": bytes.size()}
	var version := int(bytes.decode_u32(4))
	if version != FORMAT_VERSION:
		return {"ok": false, "error": "bad-version", "bytes": bytes.size()}
	var vertex_count := int(bytes.decode_u32(8))
	var expected := HEADER_BYTES + vertex_count * VERTEX_BYTES
	if expected != bytes.size():
		return {"ok": false, "error": "size-mismatch", "bytes": bytes.size(), "vertices": vertex_count}

	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	positions.resize(vertex_count)
	normals.resize(vertex_count)
	colors.resize(vertex_count)
	var offset := HEADER_BYTES
	for index in range(vertex_count):
		positions[index] = Vector3(
			bytes.decode_float(offset),
			bytes.decode_float(offset + 4),
			bytes.decode_float(offset + 8)
		)
		normals[index] = Vector3(
			bytes.decode_float(offset + 12),
			bytes.decode_float(offset + 16),
			bytes.decode_float(offset + 20)
		)
		colors[index] = Color8(
			int(bytes[offset + 24]),
			int(bytes[offset + 25]),
			int(bytes[offset + 26]),
			int(bytes[offset + 27])
		)
		offset += VERTEX_BYTES
	return {
		"ok": true,
		"positions": positions,
		"normals": normals,
		"colors": colors,
		"bytes": bytes.size(),
		"vertices": vertex_count,
	}

static func combine_chunks(specs: Array, cached_chunks: Dictionary) -> Dictionary:
	var decoded_chunks: Dictionary = {}
	var chunks: Array[Dictionary] = []
	var total_vertices := 0
	var total_bytes := 0
	var cache_hits := 0
	var cache_misses := 0
	for spec_value in specs:
		var spec: Dictionary = spec_value
		var key := String(spec.get("key", ""))
		var chunk: Dictionary
		if cached_chunks.has(key):
			chunk = cached_chunks[key]
			cache_hits += 1
		else:
			chunk = decode_file(String(spec.get("path", "")))
			cache_misses += 1
			if not bool(chunk.get("ok", false)):
				return {
					"ok": false,
					"error": "%s:%s" % [key, String(chunk.get("error", "decode"))],
					"cache_hits": cache_hits,
					"cache_misses": cache_misses,
				}
			decoded_chunks[key] = chunk
		total_vertices += int(chunk.get("vertices", 0))
		total_bytes += int(chunk.get("bytes", 0))
		chunks.append({"chunk": chunk, "origin_world": spec.get("origin_world", Vector3.ZERO)})

	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	positions.resize(total_vertices)
	normals.resize(total_vertices)
	colors.resize(total_vertices)
	var cursor := 0
	for entry in chunks:
		var chunk: Dictionary = entry["chunk"]
		var origin_world: Vector3 = entry["origin_world"]
		var chunk_positions: PackedVector3Array = chunk["positions"]
		var chunk_normals: PackedVector3Array = chunk["normals"]
		var chunk_colors: PackedColorArray = chunk["colors"]
		for index in range(chunk_positions.size()):
			positions[cursor] = chunk_positions[index] + origin_world
			normals[cursor] = chunk_normals[index]
			colors[cursor] = chunk_colors[index]
			cursor += 1
	return {
		"ok": true,
		"positions": positions,
		"normals": normals,
		"colors": colors,
		"decoded_chunks": decoded_chunks,
		"vertices": total_vertices,
		"bytes": total_bytes,
		"cache_hits": cache_hits,
		"cache_misses": cache_misses,
	}

static func arrays_for_mesh(stage: Dictionary) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = stage.get("positions", PackedVector3Array())
	arrays[Mesh.ARRAY_NORMAL] = stage.get("normals", PackedVector3Array())
	arrays[Mesh.ARRAY_COLOR] = stage.get("colors", PackedColorArray())
	return arrays
