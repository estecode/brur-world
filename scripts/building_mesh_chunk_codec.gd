extends RefCounted
class_name BuildingMeshChunkCodec

## Decodes prebuilt binary building render chunks off the presentation path.
##
## Dependencies:
## - Consumes production BMC2 chunks and compact derived BMC3 Windows-pack chunks.
## - Owns no camera, SceneTree, material, or world-streaming policy.

const MAGIC_BMC2 := "BMC2"
const MAGIC_BMC3 := "BMC3"
const FORMAT_BMC2 := 2
const FORMAT_BMC3 := 3
const HEADER_BYTES := 12
const BMC2_RECORD_BYTES := 12
const BMC2_VERTEX_BYTES := 28
const BMC3_RECORD_BYTES := 28
const BMC3_VERTEX_BYTES := 9
const BMC3_SCALE_M := 0.1
const BMC3_MODE_COMPACT := 0
const BMC3_MODE_RAW := 1
const MAX_MESH_BATCH_VERTICES := 12000

static func _signed_u8(value: int) -> int:
	return value - 256 if value > 127 else value

static func _signed_u16(value: int) -> int:
	return value - 65536 if value > 32767 else value

static func _decode_bmc2(bytes: PackedByteArray, vertex_count: int) -> Dictionary:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	positions.resize(vertex_count)
	normals.resize(vertex_count)
	colors.resize(vertex_count)
	var offset := HEADER_BYTES
	var cursor := 0
	while offset < bytes.size():
		if offset + BMC2_RECORD_BYTES > bytes.size():
			return {"ok": false, "error": "short-record-header", "bytes": bytes.size(), "vertices": vertex_count}
		var record_x := bytes.decode_float(offset)
		var record_z := bytes.decode_float(offset + 4)
		var record_vertices := int(bytes.decode_u32(offset + 8))
		offset += BMC2_RECORD_BYTES
		var record_size := record_vertices * BMC2_VERTEX_BYTES
		if record_vertices < 0 or offset + record_size > bytes.size() or cursor + record_vertices > vertex_count:
			return {"ok": false, "error": "record-size-mismatch", "bytes": bytes.size(), "vertices": vertex_count}
		for _index in range(record_vertices):
			positions[cursor] = Vector3(
				bytes.decode_float(offset) + record_x,
				bytes.decode_float(offset + 4),
				bytes.decode_float(offset + 8) + record_z
			)
			normals[cursor] = Vector3(
				bytes.decode_float(offset + 12),
				bytes.decode_float(offset + 16),
				bytes.decode_float(offset + 20)
			)
			colors[cursor] = Color8(
				int(bytes[offset + 24]),
				int(bytes[offset + 25]),
				int(bytes[offset + 26]),
				int(bytes[offset + 27])
			)
			offset += BMC2_VERTEX_BYTES
			cursor += 1
	if offset != bytes.size() or cursor != vertex_count:
		return {"ok": false, "error": "vertex-count-mismatch", "bytes": bytes.size(), "vertices": vertex_count}
	return {
		"ok": true,
		"positions": positions,
		"normals": normals,
		"colors": colors,
		"bytes": bytes.size(),
		"vertices": vertex_count,
		"format": FORMAT_BMC2,
	}

static func _decode_bmc3(bytes: PackedByteArray, vertex_count: int) -> Dictionary:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	positions.resize(vertex_count)
	normals.resize(vertex_count)
	colors.resize(vertex_count)
	var offset := HEADER_BYTES
	var cursor := 0
	while offset < bytes.size():
		if offset + BMC3_RECORD_BYTES > bytes.size():
			return {"ok": false, "error": "short-compact-record-header", "bytes": bytes.size(), "vertices": vertex_count}
		var record_x := bytes.decode_float(offset)
		var record_z := bytes.decode_float(offset + 4)
		var record_vertices := int(bytes.decode_u32(offset + 8))
		var mode := int(bytes[offset + 12])
		var palette_offset := offset + 16
		offset += BMC3_RECORD_BYTES
		if record_vertices < 0 or cursor + record_vertices > vertex_count:
			return {"ok": false, "error": "compact-record-count-mismatch", "bytes": bytes.size(), "vertices": vertex_count}
		if mode == BMC3_MODE_COMPACT:
			var record_size := record_vertices * BMC3_VERTEX_BYTES
			if offset + record_size > bytes.size():
				return {"ok": false, "error": "short-compact-vertex-payload", "bytes": bytes.size(), "vertices": vertex_count}
			for _index in range(record_vertices):
				var qx := _signed_u16(int(bytes.decode_u16(offset)))
				var qy := _signed_u16(int(bytes.decode_u16(offset + 2)))
				var qz := _signed_u16(int(bytes.decode_u16(offset + 4)))
				var nx := float(_signed_u8(int(bytes[offset + 6]))) / 127.0
				var nz := float(_signed_u8(int(bytes[offset + 7]))) / 127.0
				var meta := int(bytes[offset + 8])
				var color_index := meta & 0x03
				if color_index > 2:
					return {"ok": false, "error": "bad-compact-color-index", "bytes": bytes.size(), "vertices": vertex_count}
				positions[cursor] = Vector3(
					float(qx) * BMC3_SCALE_M + record_x,
					float(qy) * BMC3_SCALE_M,
					float(qz) * BMC3_SCALE_M + record_z
				)
				if (meta & 0x04) != 0:
					normals[cursor] = Vector3.UP
				else:
					var wall_normal := Vector3(nx, 0.0, nz)
					normals[cursor] = wall_normal.normalized() if wall_normal.length_squared() > 0.000001 else Vector3.FORWARD
				var color_offset := palette_offset + color_index * 4
				colors[cursor] = Color8(
					int(bytes[color_offset]),
					int(bytes[color_offset + 1]),
					int(bytes[color_offset + 2]),
					int(bytes[color_offset + 3])
				)
				offset += BMC3_VERTEX_BYTES
				cursor += 1
		elif mode == BMC3_MODE_RAW:
			var raw_size := record_vertices * BMC2_VERTEX_BYTES
			if offset + raw_size > bytes.size():
				return {"ok": false, "error": "short-raw-fallback-payload", "bytes": bytes.size(), "vertices": vertex_count}
			for _index in range(record_vertices):
				positions[cursor] = Vector3(
					bytes.decode_float(offset) + record_x,
					bytes.decode_float(offset + 4),
					bytes.decode_float(offset + 8) + record_z
				)
				normals[cursor] = Vector3(
					bytes.decode_float(offset + 12),
					bytes.decode_float(offset + 16),
					bytes.decode_float(offset + 20)
				)
				colors[cursor] = Color8(
					int(bytes[offset + 24]),
					int(bytes[offset + 25]),
					int(bytes[offset + 26]),
					int(bytes[offset + 27])
				)
				offset += BMC2_VERTEX_BYTES
				cursor += 1
		else:
			return {"ok": false, "error": "bad-compact-record-mode", "bytes": bytes.size(), "vertices": vertex_count}
	if offset != bytes.size() or cursor != vertex_count:
		return {"ok": false, "error": "compact-vertex-count-mismatch", "bytes": bytes.size(), "vertices": vertex_count}
	return {
		"ok": true,
		"positions": positions,
		"normals": normals,
		"colors": colors,
		"bytes": bytes.size(),
		"vertices": vertex_count,
		"format": FORMAT_BMC3,
	}

static func decode_file(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < HEADER_BYTES:
		return {"ok": false, "error": "short-header", "bytes": bytes.size()}
	var magic := bytes.slice(0, 4).get_string_from_ascii()
	var version := int(bytes.decode_u32(4))
	var vertex_count := int(bytes.decode_u32(8))
	if magic == MAGIC_BMC2 and version == FORMAT_BMC2:
		return _decode_bmc2(bytes, vertex_count)
	if magic == MAGIC_BMC3 and version == FORMAT_BMC3:
		return _decode_bmc3(bytes, vertex_count)
	return {"ok": false, "error": "bad-format", "bytes": bytes.size()}

static func stage_chunks(specs: Array, cached_chunks: Dictionary) -> Dictionary:
	var decoded_chunks: Dictionary = {}
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
		render_batches.append_array(split_mesh_batches(render_chunk))
	return {
		"ok": true,
		"render_chunks": render_batches,
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
