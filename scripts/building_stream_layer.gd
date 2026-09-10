extends Node3D
class_name BuildingStreamLayer

## Streams one batched building mesh per existing world tile from an ephemeral Malmö cache.
##
## Dependencies:
## - building_mesh_builder.gd builds tile-local meshes from existing OSM building records.
## - world_coordinates.gd is supplied explicitly by composition and remains the coordinate owner.
## - A camera rig with get_focus_world()/get_altitude() supplies presentation/streaming state.

const BuildingMeshBuilderScript = preload("res://scripts/building_mesh_builder.gd")

@export var cache_dir: String = "res://.poc_runtime/buildings"
@export var active_radius_tiles: int = 1
@export var builds_per_frame: int = 1
@export var appear_altitude_m: float = 14000.0
@export var full_height_altitude_m: float = 2500.0
@export var base_height_m: float = 24.0

var _coordinates = null
var _camera_rig: Node = null
var _active: Dictionary = {}
var _pending: Array[Vector2i] = []
var _wanted: Dictionary = {}
var _last_center_tile := Vector2i(999999, 999999)
var _last_visible := false
var _material: StandardMaterial3D = null
var _perf_build_ms: float = 0.0
var _perf_build_max_ms: float = 0.0
var _perf_tiles_built: int = 0

func setup(world_coordinates, camera_rig: Node) -> void:
	_coordinates = world_coordinates
	_camera_rig = camera_rig
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(0.50, 0.51, 0.53, 1.0)
	_material.roughness = 0.92
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_refresh(true)

func _process(_delta: float) -> void:
	if _coordinates == null or _camera_rig == null:
		return
	_refresh(false)
	_process_pending()
	_apply_altitude_blend()

func _refresh(force: bool) -> void:
	var visible_now := float(_camera_rig.call("get_altitude")) < appear_altitude_m
	if not visible_now:
		if force or _last_visible:
			_clear_all()
		_last_visible = false
		return
	_last_visible = true
	var focus: Vector3 = _camera_rig.call("get_focus_world")
	var center_tile: Vector2i = _coordinates.world_to_tile(focus)
	if not force and center_tile == _last_center_tile:
		return
	_last_center_tile = center_tile
	_wanted.clear()
	_pending.clear()
	for ty in range(center_tile.y - active_radius_tiles, center_tile.y + active_radius_tiles + 1):
		for tx in range(center_tile.x - active_radius_tiles, center_tile.x + active_radius_tiles + 1):
			var tile := Vector2i(tx, ty)
			var path := _tile_path(tile)
			if not FileAccess.file_exists(path):
				continue
			_wanted[tile] = true
			if not _active.has(tile):
				_pending.append(tile)
	for tile_value in _active.keys():
		if _wanted.has(tile_value):
			continue
		var instance: Node = _active[tile_value] as Node
		if instance != null:
			instance.queue_free()
		_active.erase(tile_value)

func _process_pending() -> void:
	var built := 0
	while built < maxi(1, builds_per_frame) and not _pending.is_empty():
		var tile: Vector2i = _pending.pop_front()
		if _active.has(tile) or not _wanted.has(tile):
			continue
		var started := Time.get_ticks_usec()
		var instance := _build_tile(tile)
		var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
		_perf_build_ms += elapsed
		_perf_build_max_ms = maxf(_perf_build_max_ms, elapsed)
		if instance != null:
			add_child(instance)
			_active[tile] = instance
			_perf_tiles_built += 1
		built += 1

func _build_tile(tile: Vector2i) -> MeshInstance3D:
	var records := _read_tile_records(_tile_path(tile))
	if records.is_empty():
		return null
	var tile_origin_absolute: Vector2 = _coordinates.tile_origin_absolute(tile)
	var mesh: ArrayMesh = BuildingMeshBuilderScript.build_tile_mesh(records, tile_origin_absolute)
	if mesh == null:
		return null
	var instance := MeshInstance3D.new()
	instance.name = "Buildings_%d_%d" % [tile.x, tile.y]
	instance.mesh = mesh
	instance.material_override = _material
	instance.position = _coordinates.tile_origin_world(tile, base_height_m)
	return instance

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

func _apply_altitude_blend() -> void:
	if _active.is_empty():
		return
	var altitude := float(_camera_rig.call("get_altitude"))
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
	return "%s/%d_%d.jsonl" % [cache_dir, tile.x, tile.y]

func _clear_all() -> void:
	_pending.clear()
	_wanted.clear()
	for node_value in _active.values():
		var node := node_value as Node
		if node != null:
			node.queue_free()
	_active.clear()

func active_tile_count() -> int:
	return _active.size()

func pending_tile_count() -> int:
	return _pending.size()

func active_mesh_count() -> int:
	return _active.size()

func consume_perf_metrics() -> Dictionary:
	var result := {
		"building_build_ms": _perf_build_ms,
		"building_build_max_ms": _perf_build_max_ms,
		"building_tiles_built": _perf_tiles_built,
		"building_active_tiles": _active.size(),
		"building_pending_tiles": _pending.size(),
	}
	_perf_build_ms = 0.0
	_perf_build_max_ms = 0.0
	_perf_tiles_built = 0
	return result
