extends RefCounted
class_name BuildingMeshChunkCodec

## Decodes prebuilt binary building render chunks off the presentation path.
##
## Dependencies:
## - Consumes only the BUILDING_MESH_LOD BMC1 binary format from the offline builder.
## - Owns no camera, SceneTree, material, or world-streaming policy.

const MAGIC := "BMC1"
const FORMAT_VERSION := 1
const HEADER_BYTES := 12
const VERTEX_BYTES := 28
const MAX_MESH_BATCH_VERTICES := 12000

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

static func stage_chunks(specs: Array, cached_chunks: Dictionary) -> Dictionary:
	var decoded_chunks: Dictionary = {}
	var render_chunks: Array = []
	var render_batches: Array = []
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
			if chunk.get("ok", false) != true:
				return {
					"ok": false,
					"error": "%s:%s" % [key, String(chunk.get("error", "decode"))],
					"cache_hits": cache_hits,
					"cache_misses": cache_misses,
				}
			decoded_chunks[key] = chunk
		total_vertices += int(chunk.get("vertices", 0))
		total_bytes += int(chunk.get("bytes", 0))
		var render_chunk := {
			"key": key,
			"positions": chunk.get("positions", PackedVector3Array()),
			"normals": chunk.get("normals", PackedVector3Array()),
			"colors": chunk.get("colors", PackedColorArray()),
			"origin_world": spec.get("origin_world", Vector3.ZERO),
			"vertices": int(chunk.get("vertices", 0)),
		}
		render_chunks.append(render_chunk)
		render_batches.append_array(split_mesh_batches(render_chunk))
	return {
		"ok": true,
		"render_chunks": render_chunks,
		"render_batches": render_batches,
		"decoded_chunks": decoded_chunks,
		"vertices": total_vertices,
		"bytes": total_bytes,
		"cache_hits": cache_hits,
		"cache_misses": cache_misses,
	}

static func split_mesh_batches(chunk: Dictionary, max_vertices: int = MAX_MESH_BATCH_VERTICES) -> Array:
	var positions: PackedVector3Array = chunk.get("positions", PackedVector3Array())
	var normals: PackedVector3Array = chunk.get("normals", PackedVector3Array())
	var colors: PackedColorArray = chunk.get("colors", PackedColorArray())
	var result: Array = []
	if positions.is_empty():
		return result
	var triangle_aligned_limit := maxi(3, max_vertices - (max_vertices % 3))
	var start := 0
	var batch_index := 0
	while start < positions.size():
		var end := mini(positions.size(), start + triangle_aligned_limit)
		if end < positions.size():
			end -= (end - start) % 3
		if end <= start:
			end = mini(positions.size(), start + 3)
		result.append({
			"key": "%s#%d" % [String(chunk.get("key", "")), batch_index],
			"source_key": String(chunk.get("key", "")),
			"positions": positions.slice(start, end),
			"normals": normals.slice(start, end),
			"colors": colors.slice(start, end),
			"origin_world": chunk.get("origin_world", Vector3.ZERO),
			"vertices": end - start,
		})
		start = end
		batch_index += 1
	return result

static func combine_chunks(specs: Array, cached_chunks: Dictionary) -> Dictionary:
	# Kept as a deterministic/reference helper for tests and tooling. Production
	# presentation uses stage_chunks() so it never creates one giant viewport array.
	var staged := stage_chunks(specs, cached_chunks)
	if staged.get("ok", false) != true:
		return staged
	var total_vertices := int(staged.get("vertices", 0))
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	positions.resize(total_vertices)
	normals.resize(total_vertices)
	colors.resize(total_vertices)
	var cursor := 0
	for entry_value in staged.get("render_chunks", []):
		var entry: Dictionary = entry_value
		var origin_world: Vector3 = entry.get("origin_world", Vector3.ZERO)
		var chunk_positions: PackedVector3Array = entry.get("positions", PackedVector3Array())
		var chunk_normals: PackedVector3Array = entry.get("normals", PackedVector3Array())
		var chunk_colors: PackedColorArray = entry.get("colors", PackedColorArray())
		for index in range(chunk_positions.size()):
			positions[cursor] = chunk_positions[index] + origin_world
			normals[cursor] = chunk_normals[index]
			colors[cursor] = chunk_colors[index]
			cursor += 1
	staged["positions"] = positions
	staged["normals"] = normals
	staged["colors"] = colors
	return staged

static func arrays_for_mesh(data: Dictionary) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.get("positions", PackedVector3Array())
	arrays[Mesh.ARRAY_NORMAL] = data.get("normals", PackedVector3Array())
	arrays[Mesh.ARRAY_COLOR] = data.get("colors", PackedColorArray())
	return arrays
