extends Node3D
class_name BuildingStreamLayer

## Streams batched building tiles with bounded work, hysteresis, directional prefetch, and metrics.
##
## Dependencies:
## - building_mesh_builder.gd builds tile-local meshes from existing OSM-derived building records.
## - world_coordinates.gd is supplied explicitly by composition and remains the coordinate owner.
## - world_stream_request.gd carries camera demand without owning layer policy.
## - Composition supplies a camera rig and an explicit directory containing tile JSONL building records.

const BuildingMeshBuilderScript = preload("res://scripts/building_mesh_builder.gd")
const WorldStreamRequestScript = preload("res://scripts/world_stream_request.gd")

const STATE_REQUESTED := "requested"
const STATE_PREPARING := "preparing"
const STATE_READY := "ready"
const STATE_VISIBLE := "visible"

@export var active_radius_tiles: int = 1
@export var builds_per_frame: int = 1
@export var build_budget_ms: float = 4.0
@export var max_pending_tiles: int = 24
@export var prefetch_tiles_ahead: int = 1
@export var appear_altitude_m: float = 14000.0
@export var hide_altitude_m: float = 15000.0
@export var full_height_altitude_m: float = 2500.0
@export var base_height_m: float = 0.0

var _coordinates = null
var _camera_rig: Node = null
var _tile_data_dir: String = ""
var _active: Dictionary = {}
var _pending: Array[Vector2i] = []
var _wanted: Dictionary = {}
var _tile_states: Dictionary = {}
var _tile_record_counts: Dictionary = {}
var _last_center_tile := Vector2i(999999, 999999)
var _last_visible := false
var _last_focus_world := Vector3.ZERO
var _has_last_focus := false
var _material: StandardMaterial3D = null
var _perf_build_ms: float = 0.0
var _perf_build_max_ms: float = 0.0
var _perf_tiles_built: int = 0
var _perf_records_built: int = 0
var _perf_dropped_requests: int = 0

func setup(world_coordinates, camera_rig: Node, tile_data_dir: String) -> void:
	assert(world_coordinates != null, "BuildingStreamLayer requires WorldCoordinates")
	assert(camera_rig != null, "BuildingStreamLayer requires a camera rig")
	assert(not tile_data_dir.is_empty(), "BuildingStreamLayer requires an explicit tile data directory")
	_coordinates = world_coordinates
	_camera_rig = camera_rig
	_tile_data_dir = tile_data_dir.trim_suffix("/")
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.50, 0.51, 0.53, 1.0)
	_material.roughness = 0.92
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var focus: Vector3 = _camera_rig.call("get_focus_world")
	_last_focus_world = focus
	_has_last_focus = true
	_refresh(WorldStreamRequestScript.new(focus, float(_camera_rig.call("get_altitude"))), true)

func _process(_delta: float) -> void:
	if _coordinates == null or _camera_rig == null:
		return
	var focus: Vector3 = _camera_rig.call("get_focus_world")
	var motion := Vector3.ZERO
	if _has_last_focus:
		motion = focus - _last_focus_world
	_last_focus_world = focus
	_has_last_focus = true
	var request = WorldStreamRequestScript.new(focus, float(_camera_rig.call("get_altitude")), motion)
	_refresh(request, false)
	_process_pending()
	_apply_altitude_blend(request.altitude_m)

func _refresh(request, force: bool) -> void:
	var visible_now := _visibility_with_hysteresis(request.altitude_m)
	if not visible_now:
		if force or _last_visible:
			_clear_all()
		_last_visible = false
		return
	var became_visible := not _last_visible
	_last_visible = true
	var center_tile: Vector2i = _coordinates.world_to_tile(request.focus_world)
	var prefetch_offset := _prefetch_offset(request)
	if not force and not became_visible and center_tile == _last_center_tile and prefetch_offset == Vector2i.ZERO:
		return
	_last_center_tile = center_tile
	_wanted.clear()
	var ordered: Array[Vector2i] = []
	_append_tile_square(ordered, center_tile, active_radius_tiles)
	if prefetch_offset != Vector2i.ZERO:
		_append_tile_square(ordered, center_tile + prefetch_offset, active_radius_tiles)

	for tile in ordered:
		var path := _tile_path(tile)
		if not FileAccess.file_exists(path):
			continue
		_wanted[tile] = true
		if not _active.has(tile) and not _pending.has(tile):
			if _pending.size() >= maxi(1, max_pending_tiles):
				_perf_dropped_requests += 1
				continue
			_pending.append(tile)
			_tile_states[tile] = STATE_REQUESTED

	for tile_value in _active.keys():
		if not _wanted.has(tile_value):
			_unload_tile(tile_value)

	var retained: Array[Vector2i] = []
	for pending_tile in _pending:
		if _wanted.has(pending_tile):
			retained.append(pending_tile)
		else:
			_tile_states.erase(pending_tile)
	_pending = retained

func _visibility_with_hysteresis(altitude_m: float) -> bool:
	if _last_visible:
		return altitude_m < hide_altitude_m
	return altitude_m < appear_altitude_m

func _prefetch_offset(request) -> Vector2i:
	if prefetch_tiles_ahead <= 0:
		return Vector2i.ZERO
	var motion: Vector2 = request.horizontal_motion()
	if motion.length() < 1.0:
		return Vector2i.ZERO
	var x_step := 0
	var y_step := 0
	if absf(motion.x) >= absf(motion.y):
		x_step = 1 if motion.x > 0.0 else -1
	else:
		y_step = -1 if motion.y > 0.0 else 1
	return Vector2i(x_step, y_step) * prefetch_tiles_ahead

func _append_tile_square(target: Array[Vector2i], center: Vector2i, radius: int) -> void:
	for ty in range(center.y - radius, center.y + radius + 1):
		for tx in range(center.x - radius, center.x + radius + 1):
			var tile := Vector2i(tx, ty)
			if not target.has(tile):
				target.append(tile)

func _process_pending() -> void:
	var built := 0
	var frame_started := Time.get_ticks_usec()
	while built < maxi(1, builds_per_frame) and not _pending.is_empty():
		if built > 0 and _elapsed_ms(frame_started) >= maxf(0.1, build_budget_ms):
			break
		var tile: Vector2i = _pending.pop_front()
		if _active.has(tile) or not _wanted.has(tile):
			continue
		_tile_states[tile] = STATE_PREPARING
		var started := Time.get_ticks_usec()
		var build_result := _build_tile(tile)
		var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
		_perf_build_ms += elapsed
		_perf_build_max_ms = maxf(_perf_build_max_ms, elapsed)
		var instance: MeshInstance3D = build_result.get("instance")
		if instance != null:
			_tile_states[tile] = STATE_READY
			add_child(instance)
			_active[tile] = instance
			_tile_record_counts[tile] = int(build_result.get("records", 0))
			_tile_states[tile] = STATE_VISIBLE
			_perf_tiles_built += 1
			_perf_records_built += int(build_result.get("records", 0))
		else:
			_tile_states.erase(tile)
		built += 1

func _elapsed_ms(started_usec: int) -> float:
	return float(Time.get_ticks_usec() - started_usec) / 1000.0

func _build_tile(tile: Vector2i) -> Dictionary:
	var records := _read_tile_records(_tile_path(tile))
	if records.is_empty():
		return {"instance": null, "records": 0}
	var tile_origin_absolute: Vector2 = _coordinates.tile_origin_absolute(tile)
	var mesh: ArrayMesh = BuildingMeshBuilderScript.build_tile_mesh(records, tile_origin_absolute)
	if mesh == null:
		return {"instance": null, "records": records.size()}
	var instance := MeshInstance3D.new()
	instance.name = "Buildings_%s" % _coordinates.tile_identity(tile).replace(":", "_")
	instance.mesh = mesh
	instance.material_override = _material
	instance.position = _coordinates.tile_origin_world(tile, base_height_m)
	return {"instance": instance, "records": records.size()}

func _read_tile_records(path: String) -> Array:
	var result: Array = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	while not file.eof_reached():
		var line := file.get_line()
		if line.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(line)
		if typeof(parsed) == TYPE_DICTIONARY:
			result.append(parsed)
	return result

func _apply_altitude_blend(altitude: float) -> void:
	if _active.is_empty():
		return
	var blend := 1.0
	if altitude > full_height_altitude_m:
		blend = 1.0 - inverse_lerp(full_height_altitude_m, appear_altitude_m, altitude)
	blend = clampf(blend, 0.0, 1.0)
	var eased := blend * blend * (3.0 - 2.0 * blend)
	for node_value in _active.values():
		var instance := node_value as MeshInstance3D
		if instance != null:
			instance.scale.y = maxf(0.02, eased)
			instance.visible = eased > 0.01

func _tile_path(tile: Vector2i) -> String:
	return "%s/%d_%d.jsonl" % [_tile_data_dir, tile.x, tile.y]

func _unload_tile(tile: Vector2i) -> void:
	var instance: Node = _active.get(tile) as Node
	if instance != null:
		instance.queue_free()
	_active.erase(tile)
	_tile_record_counts.erase(tile)
	_tile_states.erase(tile)

func _clear_all() -> void:
	_pending.clear()
	_wanted.clear()
	for tile in _active.keys():
		_unload_tile(tile)
	_tile_states.clear()

func active_tile_count() -> int:
	return _active.size()

func pending_tile_count() -> int:
	return _pending.size()

func active_mesh_count() -> int:
	return _active.size()

func tile_state(tile: Vector2i) -> String:
	return String(_tile_states.get(tile, "unloaded"))

func debug_snapshot() -> Dictionary:
	var ids: Array[String] = []
	for tile in _active.keys():
		ids.append(_coordinates.tile_identity(tile))
	ids.sort()
	var records := 0
	for count in _tile_record_counts.values():
		records += int(count)
	return {
		"active_tiles": _active.size(),
		"pending_tiles": _pending.size(),
		"wanted_tiles": _wanted.size(),
		"active_tile_ids": ids,
		"active_records": records,
		"last_center_tile": _coordinates.tile_identity(_last_center_tile) if _coordinates != null else "",
	}

func consume_perf_metrics() -> Dictionary:
	var result := {
		"building_build_ms": _perf_build_ms,
		"building_build_max_ms": _perf_build_max_ms,
		"building_tiles_built": _perf_tiles_built,
		"building_records_built": _perf_records_built,
		"building_active_tiles": _active.size(),
		"building_pending_tiles": _pending.size(),
		"building_dropped_requests": _perf_dropped_requests,
	}
	_perf_build_ms = 0.0
	_perf_build_max_ms = 0.0
	_perf_tiles_built = 0
	_perf_records_built = 0
	_perf_dropped_requests = 0
	return result
