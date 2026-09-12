extends Node3D
class_name BuildingStreamLayer

## Stages complete camera-visible prebuilt building LOD chunks off-thread and swaps the viewport atomically.
##
## Dependencies:
## - building_lod_policy.gd selects altitude detail and spatial chunk scale.
## - building_mesh_chunk_codec.gd decodes prebuilt BMC1 render chunks without triangulation.
## - world_coordinates.gd is supplied explicitly by composition and remains the coordinate owner.
## - Composition supplies a camera rig and the derived building_mesh_lod directory.

const BuildingLodPolicyScript = preload("res://scripts/building_lod_policy.gd")
const BuildingMeshChunkCodecScript = preload("res://scripts/building_mesh_chunk_codec.gd")

@export var view_margin_chunks: int = 1
@export var max_view_chunks: int = 64
@export var max_cache_chunks: int = 96
@export var prepare_budget_ms: float = 4.0
@export var appear_altitude_m: float = 14000.0
@export var hide_altitude_m: float = 15000.0
@export var full_height_altitude_m: float = 2500.0
@export var base_height_m: float = 0.0
@export var cast_shadows: bool = false
@export var streaming_enabled: bool = true

var _coordinates = null
var _camera_rig: Node = null
var _mesh_data_dir := ""
var _material: StandardMaterial3D = null
var _active_group: Node3D = null
var _active_signature := ""
var _active_lod := -1
var _active_chunks := 0
var _active_vertices := 0
var _desired_request: Dictionary = {}
var _desired_signature := ""
var _last_visible := false
var _request_generation := 0
var _stage_thread: Thread = null
var _stage_generation := -1
var _cache: Dictionary = {}
var _cache_lru: Array[String] = []

var _prepared_group: Node3D = null
var _prepare_queue: Array = []
var _prepare_request: Dictionary = {}
var _prepare_stage: Dictionary = {}
var _prepare_generation := -1
var _prepared_ready := false

var _perf_stage_ms := 0.0
var _perf_stage_max_ms := 0.0
var _perf_prepare_ms := 0.0
var _perf_prepare_max_ms := 0.0
var _perf_publish_ms := 0.0
var _perf_publish_max_ms := 0.0
var _perf_cache_hits := 0
var _perf_cache_misses := 0
var _perf_bytes_loaded := 0
var _perf_chunks_loaded := 0
var _perf_stale_stages := 0
var _last_stage_ms := 0.0
var _last_prepare_ms := 0.0
var _last_publish_ms := 0.0

func setup(world_coordinates, camera_rig: Node, mesh_data_dir: String) -> void:
	assert(world_coordinates != null, "BuildingStreamLayer requires WorldCoordinates")
	assert(camera_rig != null, "BuildingStreamLayer requires a camera rig")
	assert(not mesh_data_dir.is_empty(), "BuildingStreamLayer requires an explicit mesh LOD directory")
	_coordinates = world_coordinates
	_camera_rig = camera_rig
	_mesh_data_dir = mesh_data_dir.trim_suffix("/")
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color.WHITE
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.92
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	set_process(streaming_enabled)
	if streaming_enabled:
		_update_desired_request(true)
	else:
		_clear_presentation()

func _exit_tree() -> void:
	if _stage_thread != null and _stage_thread.is_started():
		_stage_thread.wait_to_finish()

func set_streaming_enabled(enabled: bool) -> void:
	if streaming_enabled == enabled:
		return
	streaming_enabled = enabled
	set_process(enabled)
	if not enabled:
		_request_generation += 1
		_desired_request.clear()
		_desired_signature = ""
		_last_visible = false
		_cancel_hidden_prepare()
		_clear_presentation()
		return
	if _coordinates == null or _camera_rig == null:
		return
	_update_desired_request(true)

func is_streaming_enabled() -> bool:
	return streaming_enabled

func is_viewport_ready() -> bool:
	return (
		streaming_enabled
		and not _desired_signature.is_empty()
		and _active_signature == _desired_signature
		and not _stage_in_flight()
		and not _prepare_in_progress()
		and not _prepared_ready
	)

func _process(_delta: float) -> void:
	if not streaming_enabled or _coordinates == null or _camera_rig == null:
		return
	_poll_stage()
	_update_desired_request(false)
	if _prepared_ready:
		_publish_prepared_viewport()
	elif _prepare_in_progress():
		_prepare_hidden_step()
	_start_stage_if_needed()
	_apply_altitude_blend(float(_camera_rig.call("get_altitude")))

func _update_desired_request(force: bool) -> void:
	var altitude := float(_camera_rig.call("get_altitude"))
	var visible_now := _visibility_with_hysteresis(altitude)
	if not visible_now:
		if force or _last_visible:
			_request_generation += 1
			_desired_request.clear()
			_desired_signature = ""
			_cancel_hidden_prepare()
			_clear_presentation()
		_last_visible = false
		return
	_last_visible = true
	var request := _select_viewport_request(altitude)
	var signature := String(request.get("signature", ""))
	if not force and signature == _desired_signature:
		return
	_request_generation += 1
	request["generation"] = _request_generation
	_desired_request = request
	_desired_signature = signature
	_cancel_hidden_prepare()
	_start_stage_if_needed()

func _select_viewport_request(altitude: float) -> Dictionary:
	var lod := BuildingLodPolicyScript.choose_lod(altitude)
	var bounds := _chunk_bounds(lod, maxi(0, view_margin_chunks))
	while _bounds_chunk_count(bounds) > maxi(1, max_view_chunks) and lod > BuildingLodPolicyScript.LOD_COARSE:
		lod -= 1
		bounds = _chunk_bounds(lod, maxi(0, view_margin_chunks))
	if _bounds_chunk_count(bounds) > maxi(1, max_view_chunks) and view_margin_chunks > 0:
		bounds = _chunk_bounds(lod, 0)

	var specs: Array[Dictionary] = []
	var chunk_size := BuildingLodPolicyScript.chunk_size_m(lod)
	for chunk_y in range(int(bounds["min_y"]), int(bounds["max_y"]) + 1):
		for chunk_x in range(int(bounds["min_x"]), int(bounds["max_x"]) + 1):
			var chunk := Vector2i(chunk_x, chunk_y)
			var path := _chunk_path(lod, chunk)
			if not FileAccess.file_exists(path):
				continue
			var absolute_origin := Vector2(float(chunk_x) * chunk_size, float(chunk_y) * chunk_size)
			specs.append({
				"key": _chunk_key(lod, chunk),
				"path": path,
				"origin_world": _coordinates.absolute_to_world(absolute_origin, base_height_m),
			})
	var signature := "L%d:%d:%d:%d:%d" % [lod, bounds["min_x"], bounds["max_x"], bounds["min_y"], bounds["max_y"]]
	return {
		"signature": signature,
		"lod": lod,
		"specs": specs,
		"coverage_chunks": _bounds_chunk_count(bounds),
		"render_chunks": specs.size(),
		"bounds": bounds,
	}

func _chunk_bounds(lod: int, margin_chunks: int) -> Dictionary:
	var chunk_size := BuildingLodPolicyScript.chunk_size_m(lod)
	var world_points: Array[Vector3] = []
	if _camera_rig.has_method("get_ground_view_corners"):
		var corners: Variant = _camera_rig.call("get_ground_view_corners")
		if typeof(corners) == TYPE_PACKED_VECTOR3_ARRAY or typeof(corners) == TYPE_ARRAY:
			for value in corners:
				if typeof(value) == TYPE_VECTOR3 and (value as Vector3).is_finite():
					world_points.append(value)
	if world_points.is_empty():
		world_points.append(_camera_rig.call("get_focus_world"))
	var first_absolute: Vector2 = _coordinates.world_to_absolute(world_points[0])
	var min_x := first_absolute.x
	var max_x := first_absolute.x
	var min_y := first_absolute.y
	var max_y := first_absolute.y
	for index in range(1, world_points.size()):
		var absolute: Vector2 = _coordinates.world_to_absolute(world_points[index])
		min_x = minf(min_x, absolute.x)
		max_x = maxf(max_x, absolute.x)
		min_y = minf(min_y, absolute.y)
		max_y = maxf(max_y, absolute.y)
	var margin_m := float(margin_chunks) * chunk_size
	return {
		"min_x": floori((min_x - margin_m) / chunk_size),
		"max_x": floori((max_x + margin_m) / chunk_size),
		"min_y": floori((min_y - margin_m) / chunk_size),
		"max_y": floori((max_y + margin_m) / chunk_size),
	}

func _bounds_chunk_count(bounds: Dictionary) -> int:
	return maxi(0, int(bounds["max_x"]) - int(bounds["min_x"]) + 1) * maxi(0, int(bounds["max_y"]) - int(bounds["min_y"]) + 1)

func _start_stage_if_needed() -> void:
	if (
		not streaming_enabled
		or _desired_request.is_empty()
		or _desired_signature == _active_signature
		or _stage_in_flight()
		or _prepare_in_progress()
		or _prepared_ready
	):
		return
	var specs: Array = _desired_request.get("specs", [])
	var cached_chunks: Dictionary = {}
	for spec_value in specs:
		var spec: Dictionary = spec_value
		var key := String(spec.get("key", ""))
		if _cache.has(key):
			cached_chunks[key] = _cache[key]
	_stage_generation = int(_desired_request.get("generation", _request_generation))
	_stage_thread = Thread.new()
	var start_error := _stage_thread.start(Callable(self, "_stage_worker").bind(_stage_generation, specs, cached_chunks))
	if start_error != OK:
		push_error("Building viewport staging thread failed to start: %s" % error_string(start_error))
		_stage_thread = null
		_stage_generation = -1

func _stage_worker(generation: int, specs: Array, cached_chunks: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	var result: Dictionary = BuildingMeshChunkCodecScript.stage_chunks(specs, cached_chunks)
	result["generation"] = generation
	result["stage_ms"] = float(Time.get_ticks_usec() - started) / 1000.0
	return result

func _poll_stage() -> void:
	if not _stage_in_flight() or _stage_thread.is_alive():
		return
	var result: Variant = _stage_thread.wait_to_finish()
	_stage_thread = null
	_stage_generation = -1
	if typeof(result) != TYPE_DICTIONARY:
		push_error("Building viewport staging returned invalid data")
		_start_stage_if_needed()
		return
	var stage: Dictionary = result
	_last_stage_ms = float(stage.get("stage_ms", 0.0))
	_perf_stage_ms += _last_stage_ms
	_perf_stage_max_ms = maxf(_perf_stage_max_ms, _last_stage_ms)
	_perf_cache_hits += int(stage.get("cache_hits", 0))
	_perf_cache_misses += int(stage.get("cache_misses", 0))
	_perf_bytes_loaded += int(stage.get("bytes", 0))
	if stage.get("ok", false) != true:
		push_error("Building viewport staging failed: %s" % String(stage.get("error", "unknown")))
		_start_stage_if_needed()
		return
	_cache_decoded_chunks(stage.get("decoded_chunks", {}))
	if int(stage.get("generation", -1)) != _request_generation:
		_perf_stale_stages += 1
		_start_stage_if_needed()
		return
	_begin_hidden_prepare(stage)

func _begin_hidden_prepare(stage: Dictionary) -> void:
	_cancel_hidden_prepare()
	_prepare_generation = int(stage.get("generation", -1))
	_prepare_request = _desired_request.duplicate(true)
	_prepare_stage = stage
	_prepare_queue = stage.get("render_chunks", []).duplicate()
	_prepared_group = Node3D.new()
	_prepared_group.name = "BuildingViewportPreparing_L%d" % int(_prepare_request.get("lod", -1))
	_prepared_group.visible = false
	add_child(_prepared_group)
	_prepared_ready = _prepare_queue.is_empty()

func _prepare_hidden_step() -> void:
	if not _prepare_in_progress():
		return
	if _prepare_generation != _request_generation:
		_cancel_hidden_prepare()
		_start_stage_if_needed()
		return
	var started := Time.get_ticks_usec()
	var budget_usec := maxi(100, int(maxf(0.1, prepare_budget_ms) * 1000.0))
	while not _prepare_queue.is_empty():
		var entry: Dictionary = _prepare_queue.pop_front()
		var positions: PackedVector3Array = entry.get("positions", PackedVector3Array())
		if not positions.is_empty():
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BuildingMeshChunkCodecScript.arrays_for_mesh(entry))
			var instance := MeshInstance3D.new()
			instance.name = "Chunk_%s" % String(entry.get("key", ""))
			instance.mesh = mesh
			instance.material_override = _material
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.position = entry.get("origin_world", Vector3.ZERO)
			_prepared_group.add_child(instance)
		if Time.get_ticks_usec() - started >= budget_usec:
			break
	_last_prepare_ms = float(Time.get_ticks_usec() - started) / 1000.0
	_perf_prepare_ms += _last_prepare_ms
	_perf_prepare_max_ms = maxf(_perf_prepare_max_ms, _last_prepare_ms)
	if _prepare_queue.is_empty():
		# Publish on the next process tick so the last mesh-preparation frame and the
		# atomic visibility swap can never combine into one main-thread spike.
		_prepared_ready = true

func _publish_prepared_viewport() -> void:
	if not _prepared_ready or _prepared_group == null or not is_instance_valid(_prepared_group):
		return
	if _prepare_generation != _request_generation:
		_cancel_hidden_prepare()
		_start_stage_if_needed()
		return
	var started := Time.get_ticks_usec()
	var previous := _active_group
	if previous != null and is_instance_valid(previous):
		previous.visible = false
	_prepared_group.visible = true
	_active_group = _prepared_group
	_active_group.name = "BuildingViewport_L%d" % int(_prepare_request.get("lod", -1))
	_active_signature = String(_prepare_request.get("signature", ""))
	_active_lod = int(_prepare_request.get("lod", -1))
	_active_chunks = int(_prepare_request.get("render_chunks", 0))
	_active_vertices = int(_prepare_stage.get("vertices", 0))
	if previous != null and is_instance_valid(previous):
		previous.queue_free()
	for spec_value in _prepare_request.get("specs", []):
		_cache_touch(String((spec_value as Dictionary).get("key", "")))
	_perf_chunks_loaded += int(_prepare_stage.get("cache_misses", 0))
	_prepared_group = null
	_prepare_queue.clear()
	_prepare_request.clear()
	_prepare_stage.clear()
	_prepare_generation = -1
	_prepared_ready = false
	_last_publish_ms = float(Time.get_ticks_usec() - started) / 1000.0
	_perf_publish_ms += _last_publish_ms
	_perf_publish_max_ms = maxf(_perf_publish_max_ms, _last_publish_ms)

func _cancel_hidden_prepare() -> void:
	if _prepared_group != null and is_instance_valid(_prepared_group):
		_prepared_group.queue_free()
	_prepared_group = null
	_prepare_queue.clear()
	_prepare_request.clear()
	_prepare_stage.clear()
	_prepare_generation = -1
	_prepared_ready = false

func _prepare_in_progress() -> bool:
	return _prepared_group != null and is_instance_valid(_prepared_group) and not _prepared_ready

func _cache_decoded_chunks(decoded: Dictionary) -> void:
	for key_value in decoded.keys():
		var key := String(key_value)
		_cache[key] = decoded[key_value]
		_cache_touch(key)
	while _cache_lru.size() > maxi(1, max_cache_chunks):
		var evicted: String = String(_cache_lru.pop_front())
		_cache.erase(evicted)

func _cache_touch(key: String) -> void:
	if key.is_empty() or not _cache.has(key):
		return
	var existing := _cache_lru.find(key)
	if existing >= 0:
		_cache_lru.remove_at(existing)
	_cache_lru.append(key)

func _stage_in_flight() -> bool:
	return _stage_thread != null and _stage_thread.is_started()

func _visibility_with_hysteresis(altitude_m: float) -> bool:
	if _last_visible:
		return altitude_m < hide_altitude_m
	return altitude_m < appear_altitude_m

func _apply_altitude_blend(altitude: float) -> void:
	if _active_group == null or not is_instance_valid(_active_group):
		return
	var blend := 1.0
	if altitude > full_height_altitude_m:
		blend = 1.0 - inverse_lerp(full_height_altitude_m, appear_altitude_m, altitude)
	blend = clampf(blend, 0.0, 1.0)
	var eased := blend * blend * (3.0 - 2.0 * blend)
	_active_group.scale.y = maxf(0.02, eased)
	_active_group.visible = eased > 0.01

func _chunk_path(lod: int, chunk: Vector2i) -> String:
	return "%s/lod%d/%d_%d.bmc" % [_mesh_data_dir, lod, chunk.x, chunk.y]

func _chunk_key(lod: int, chunk: Vector2i) -> String:
	return "L%d:%d:%d" % [lod, chunk.x, chunk.y]

func _clear_presentation() -> void:
	if _active_group != null and is_instance_valid(_active_group):
		_active_group.queue_free()
	_active_group = null
	_active_signature = ""
	_active_lod = -1
	_active_chunks = 0
	_active_vertices = 0

func active_tile_count() -> int:
	return _active_chunks

func pending_tile_count() -> int:
	return int(_desired_request.get("render_chunks", 0)) if _stage_in_flight() or _prepare_in_progress() or _prepared_ready else 0

func active_mesh_count() -> int:
	# A viewport group is the atomic presentation unit even though it contains
	# independently prepared chunk meshes internally.
	return 1 if _active_group != null and is_instance_valid(_active_group) else 0

func debug_snapshot() -> Dictionary:
	return {
		"streaming_enabled": streaming_enabled,
		"viewport_ready": is_viewport_ready(),
		"active_signature": _active_signature,
		"desired_signature": _desired_signature,
		"building_lod": _active_lod,
		"desired_lod": int(_desired_request.get("lod", -1)),
		"active_chunks": _active_chunks,
		"coverage_chunks": int(_desired_request.get("coverage_chunks", 0)),
		"render_chunks": int(_desired_request.get("render_chunks", 0)),
		"active_vertices": _active_vertices,
		"stage_in_flight": _stage_in_flight(),
		"prepare_in_progress": _prepare_in_progress(),
		"prepared_ready": _prepared_ready,
		"cache_chunks": _cache.size(),
		"last_stage_ms": _last_stage_ms,
		"last_prepare_ms": _last_prepare_ms,
		"last_publish_ms": _last_publish_ms,
	}

func consume_perf_metrics() -> Dictionary:
	var result := {
		"building_stage_ms": _perf_stage_ms,
		"building_stage_max_ms": _perf_stage_max_ms,
		"building_prepare_ms": _perf_prepare_ms,
		"building_prepare_max_ms": _perf_prepare_max_ms,
		"building_publish_ms": _perf_publish_ms,
		"building_publish_max_ms": _perf_publish_max_ms,
		"building_last_stage_ms": _last_stage_ms,
		"building_last_prepare_ms": _last_prepare_ms,
		"building_last_publish_ms": _last_publish_ms,
		"building_cache_hits": _perf_cache_hits,
		"building_cache_misses": _perf_cache_misses,
		"building_bytes_loaded": _perf_bytes_loaded,
		"building_chunks_loaded": _perf_chunks_loaded,
		"building_stale_stages": _perf_stale_stages,
		"building_active_chunks": _active_chunks,
		"building_active_vertices": _active_vertices,
		"building_cache_chunks": _cache.size(),
	}
	_perf_stage_ms = 0.0
	_perf_stage_max_ms = 0.0
	_perf_prepare_ms = 0.0
	_perf_prepare_max_ms = 0.0
	_perf_publish_ms = 0.0
	_perf_publish_max_ms = 0.0
	_perf_cache_hits = 0
	_perf_cache_misses = 0
	_perf_bytes_loaded = 0
	_perf_chunks_loaded = 0
	_perf_stale_stages = 0
	return result
