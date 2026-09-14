extends Node3D
class_name GeoDotWorldRenderer

## Bounded GeoDot presentation streamer for buildings and roads.
##
## Dependencies:
## - GeoDotWorldSource adapts the GeoPackage into BRUR render records.
## - GeoDotWorldMeshBuilder batches those records into one building + one road mesh per cell.
## - WorldCoordinates remains the only projected/world coordinate conversion owner.
## - CameraRig supplies focus/altitude. This node owns presentation only, never gameplay/collision truth.

const GeoDotWorldSourceScript = preload("res://scripts/geodot_world_source.gd")
const GeoDotWorldMeshBuilderScript = preload("res://scripts/geodot_world_mesh_builder.gd")

@export var cell_size_m := 2000.0
@export var near_radius_cells := 1
@export var far_radius_cells := 3
@export var max_resident_cells := 49
@export var max_pending_cells := 32
@export var max_buildings_per_cell := 12000
@export var max_roads_per_cell := 8000
@export var refresh_interval_s := 0.20
@export var far_lod_altitude_m := 2500.0

var _coordinates = null
var _camera_rig: Node = null
var _source = null
var _enabled := false
var _ready := false
var _refresh_accum := 0.0
var _active: Dictionary = {}
var _desired: Dictionary = {}
var _queue: Array[Dictionary] = []
var _queued: Dictionary = {}
var _query_thread: Thread = null
var _query_key := ""
var _query_generation := 0
var _generation := 0
var _building_material: StandardMaterial3D = null
var _road_material: StandardMaterial3D = null

var _perf_query_ms := 0.0
var _perf_query_max_ms := 0.0
var _perf_build_ms := 0.0
var _perf_build_max_ms := 0.0
var _perf_queries := 0
var _perf_publishes := 0
var _perf_building_features := 0
var _perf_road_features := 0

func setup(world_coordinates, camera_rig: Node, gpkg_path: String) -> Dictionary:
	assert(world_coordinates != null, "GeoDotWorldRenderer requires WorldCoordinates")
	assert(camera_rig != null, "GeoDotWorldRenderer requires CameraRig")
	_coordinates = world_coordinates
	_camera_rig = camera_rig
	_source = GeoDotWorldSourceScript.new()
	var opened: Dictionary = _source.open_dataset(gpkg_path)
	if opened.get("ok", false) != true:
		_ready = false
		_enabled = false
		return opened
	_setup_materials()
	_ready = true
	set_enabled(true)
	return opened

func _exit_tree() -> void:
	if _query_thread != null and _query_thread.is_started():
		_query_thread.wait_to_finish()

func set_enabled(value: bool) -> void:
	_enabled = value and _ready
	set_process(_enabled)
	if not _enabled:
		_generation += 1
		_queue.clear()
		_queued.clear()
		_desired.clear()
		_clear_active()
		return
	_refresh_desired(true)

func is_enabled() -> bool:
	return _enabled

func is_ready() -> bool:
	return _ready

func source_metadata() -> Dictionary:
	return _source.metadata() if _source != null else {}

func _process(delta: float) -> void:
	if not _enabled:
		return
	_poll_query()
	_refresh_accum += delta
	if _refresh_accum >= refresh_interval_s:
		_refresh_accum = 0.0
		_refresh_desired(false)
	_start_query_if_needed()

func _refresh_desired(force: bool) -> void:
	if _camera_rig == null or not _camera_rig.has_method("get_focus_world"):
		return
	var focus_world: Vector3 = _camera_rig.call("get_focus_world")
	var focus_abs: Vector2 = _coordinates.world_to_absolute(focus_world)
	var center := Vector2i(floori(focus_abs.x / cell_size_m), floori(focus_abs.y / cell_size_m))
	var altitude := float(_camera_rig.call("get_altitude")) if _camera_rig.has_method("get_altitude") else 0.0
	var next_desired: Dictionary = {}
	var candidates: Array[Dictionary] = []
	for dy in range(-far_radius_cells, far_radius_cells + 1):
		for dx in range(-far_radius_cells, far_radius_cells + 1):
			var distance_cells := maxi(absi(dx), absi(dy))
			if distance_cells > far_radius_cells:
				continue
			var cell := center + Vector2i(dx, dy)
			var lod := GeoDotWorldMeshBuilderScript.LOD_NEAR
			if distance_cells > near_radius_cells or altitude >= far_lod_altitude_m:
				lod = GeoDotWorldMeshBuilderScript.LOD_FAR
			candidates.append({"cell": cell, "lod": lod, "distance": distance_cells})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["distance"]) < int(b["distance"]))
	var limit := mini(max_resident_cells, candidates.size())
	for index in range(limit):
		var request: Dictionary = candidates[index]
		var cell: Vector2i = request["cell"]
		var key := _cell_key(cell)
		next_desired[key] = int(request["lod"])
	var changed := force or next_desired.hash() != _desired.hash()
	_desired = next_desired
	if not changed:
		return
	_generation += 1
	for key in _active.keys().duplicate():
		if _desired.has(key):
			continue
		var node: Node = (_active[key] as Dictionary).get("node")
		if node != null:
			node.queue_free()
		_active.erase(key)
	for key in _desired.keys():
		var wanted_lod := int(_desired[key])
		if _active.has(key) and int((_active[key] as Dictionary).get("lod", -1)) == wanted_lod:
			continue
		_enqueue_cell(String(key), wanted_lod)
	_trim_queue()
	_start_query_if_needed()

func _enqueue_cell(key: String, lod: int) -> void:
	var queue_id := "%s:%d" % [key, lod]
	if _queued.has(queue_id) or (_query_key == queue_id):
		return
	var cell := _parse_cell_key(key)
	_queue.append({"key": key, "queue_id": queue_id, "cell": cell, "lod": lod, "generation": _generation})
	_queued[queue_id] = true

func _trim_queue() -> void:
	while _queue.size() > maxi(1, max_pending_cells):
		var dropped: Dictionary = _queue.pop_back()
		_queued.erase(String(dropped.get("queue_id", "")))

func _start_query_if_needed() -> void:
	if _query_thread != null or _queue.is_empty() or not _enabled:
		return
	var request: Dictionary = _queue.pop_front()
	var queue_id := String(request.get("queue_id", ""))
	_queued.erase(queue_id)
	_query_key = queue_id
	_query_generation = int(request.get("generation", _generation))
	_query_thread = Thread.new()
	var error := _query_thread.start(Callable(self, "_query_worker").bind(request))
	if error != OK:
		push_error("GeoDot cell query thread failed to start: %s" % error_string(error))
		_query_thread = null
		_query_key = ""

func _query_worker(request: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec()
	var cell: Vector2i = request["cell"]
	var top_left := Vector2(float(cell.x) * cell_size_m, float(cell.y + 1) * cell_size_m)
	var result: Dictionary = _source.query_cell(top_left, cell_size_m, max_buildings_per_cell, max_roads_per_cell)
	result["request"] = request
	result["total_query_ms"] = float(Time.get_ticks_usec() - started) / 1000.0
	return result

func _poll_query() -> void:
	if _query_thread == null or _query_thread.is_alive():
		return
	var value: Variant = _query_thread.wait_to_finish()
	_query_thread = null
	_query_key = ""
	if typeof(value) != TYPE_DICTIONARY:
		push_error("GeoDot cell query returned invalid data")
		return
	var result: Dictionary = value
	if result.get("ok", false) != true:
		push_error("GeoDot cell query failed: %s" % String(result.get("error", "unknown")))
		return
	var request: Dictionary = result.get("request", {})
	var key := String(request.get("key", ""))
	var lod := int(request.get("lod", -1))
	if key.is_empty() or not _desired.has(key) or int(_desired[key]) != lod:
		return
	var query_ms := float(result.get("total_query_ms", 0.0))
	_perf_query_ms += query_ms
	_perf_query_max_ms = maxf(_perf_query_max_ms, query_ms)
	_perf_queries += 1
	_perf_building_features += int(result.get("building_features", 0))
	_perf_road_features += int(result.get("road_features", 0))
	_publish_cell(request, result)

func _publish_cell(request: Dictionary, result: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	var cell: Vector2i = request["cell"]
	var key := String(request["key"])
	var lod := int(request["lod"])
	var origin_abs := Vector2(float(cell.x) * cell_size_m, float(cell.y) * cell_size_m)
	var group := Node3D.new()
	group.name = "GeoDotCell_%d_%d_L%d" % [cell.x, cell.y, lod]
	group.position = _coordinates.absolute_to_world(origin_abs)
	group.visible = false
	var building_mesh := GeoDotWorldMeshBuilderScript.build_buildings(result.get("buildings", []), origin_abs, lod)
	if building_mesh != null:
		var building_instance := MeshInstance3D.new()
		building_instance.name = "Buildings"
		building_instance.mesh = building_mesh
		building_instance.material_override = _building_material
		group.add_child(building_instance)
	var road_mesh := GeoDotWorldMeshBuilderScript.build_roads(result.get("roads", []), origin_abs, lod)
	if road_mesh != null:
		var road_instance := MeshInstance3D.new()
		road_instance.name = "Roads"
		road_instance.mesh = road_mesh
		road_instance.position.y = 0.02
		road_instance.material_override = _road_material
		group.add_child(road_instance)
	add_child(group)
	if _active.has(key):
		var old: Node = (_active[key] as Dictionary).get("node")
		if old != null:
			old.queue_free()
	_active[key] = {"node": group, "lod": lod, "buildings": int(result.get("building_features", 0)), "roads": int(result.get("road_features", 0))}
	group.visible = true
	var build_ms := float(Time.get_ticks_usec() - started) / 1000.0
	_perf_build_ms += build_ms
	_perf_build_max_ms = maxf(_perf_build_max_ms, build_ms)
	_perf_publishes += 1

func _setup_materials() -> void:
	_building_material = StandardMaterial3D.new()
	_building_material.albedo_color = Color.WHITE
	_building_material.vertex_color_use_as_albedo = true
	_building_material.roughness = 0.92
	_building_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_road_material = StandardMaterial3D.new()
	_road_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_road_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_road_material.vertex_color_use_as_albedo = true
	_road_material.albedo_color = Color.WHITE

func _clear_active() -> void:
	for value in _active.values():
		var node: Node = (value as Dictionary).get("node")
		if node != null:
			node.queue_free()
	_active.clear()

func debug_snapshot() -> Dictionary:
	return {
		"enabled": _enabled,
		"ready": _ready,
		"active_cells": _active.size(),
		"desired_cells": _desired.size(),
		"pending_cells": _queue.size() + (1 if _query_thread != null else 0),
		"max_resident_cells": max_resident_cells,
		"max_pending_cells": max_pending_cells,
		"source": source_metadata(),
	}

func consume_perf_metrics() -> Dictionary:
	var result := {
		"geodot_query_ms": _perf_query_ms,
		"geodot_query_max_ms": _perf_query_max_ms,
		"geodot_build_ms": _perf_build_ms,
		"geodot_build_max_ms": _perf_build_max_ms,
		"geodot_queries": _perf_queries,
		"geodot_publishes": _perf_publishes,
		"geodot_building_features": _perf_building_features,
		"geodot_road_features": _perf_road_features,
		"geodot_active_cells": _active.size(),
		"geodot_pending_cells": _queue.size() + (1 if _query_thread != null else 0),
	}
	_perf_query_ms = 0.0
	_perf_query_max_ms = 0.0
	_perf_build_ms = 0.0
	_perf_build_max_ms = 0.0
	_perf_queries = 0
	_perf_publishes = 0
	_perf_building_features = 0
	_perf_road_features = 0
	return result

func _cell_key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x, cell.y]

func _parse_cell_key(key: String) -> Vector2i:
	var parts := key.split(":")
	return Vector2i(int(parts[0]), int(parts[1])) if parts.size() == 2 else Vector2i.ZERO
