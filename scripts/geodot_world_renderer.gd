extends Node3D
class_name GeoDotWorldRenderer

const Source = preload("res://scripts/geodot_world_source.gd")
const MeshBuilder = preload("res://scripts/geodot_world_mesh_builder.gd")

@export var cell_size_m := 2000.0
@export var near_radius_cells := 1
@export var far_radius_cells := 3
@export var max_view_radius_cells := 6
@export var coverage_altitude_factor := 0.72
@export var max_resident_cells := 169
@export var max_pending_cells := 96
@export var max_query_cache_cells := 192
@export var max_buildings_per_cell := 3000
@export var max_roads_per_cell := 2500
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
var _query_cache: Dictionary = {}
var _query_cache_order: Array[String] = []
var _query_thread: Thread = null
var _query_key := ""
var _generation := 0
var _building_material: StandardMaterial3D = null
var _road_material: StandardMaterial3D = null
var _perf_query_ms := 0.0
var _perf_query_max_ms := 0.0
var _perf_build_ms := 0.0
var _perf_build_max_ms := 0.0
var _perf_queries := 0
var _perf_cache_hits := 0
var _perf_publishes := 0
var _perf_building_features := 0
var _perf_road_features := 0

func setup(world_coordinates, camera_rig: Node, gpkg_path: String) -> Dictionary:
	assert(world_coordinates != null, "GeoDotWorldRenderer requires WorldCoordinates")
	assert(camera_rig != null, "GeoDotWorldRenderer requires CameraRig")
	_coordinates = world_coordinates
	_camera_rig = camera_rig
	_source = Source.new()
	var opened: Dictionary = _source.open_dataset(gpkg_path)
	if opened.get("ok", false) != true: return opened
	_setup_materials(); _ready = true; set_enabled(true)
	return opened

func _exit_tree() -> void:
	_shutdown_query_worker(); _clear_active(true); _clear_query_cache(); _release_render_resources(); _release_source()

func shutdown() -> void:
	_enabled = false; _ready = false; set_process(false); _generation += 1
	_queue.clear(); _queued.clear(); _desired.clear(); _shutdown_query_worker(); _clear_active(true); _clear_query_cache(); _release_render_resources(); _release_source()
	_coordinates = null; _camera_rig = null

func _release_render_resources() -> void:
	_building_material = null; _road_material = null

func _release_source() -> void:
	if _source != null:
		if _source.has_method("close"): _source.close()
		_source = null

func _shutdown_query_worker() -> void:
	if _query_thread != null and _query_thread.is_started(): _query_thread.wait_to_finish()
	_query_thread = null; _query_key = ""

func set_enabled(value: bool) -> void:
	_enabled = value and _ready; set_process(_enabled)
	if not _enabled:
		_generation += 1; _queue.clear(); _queued.clear(); _desired.clear(); _clear_active(); return
	_refresh_desired(true)

func is_enabled() -> bool: return _enabled
func is_ready() -> bool: return _ready
func source_metadata() -> Dictionary: return _source.metadata() if _source != null else {}

func _process(delta: float) -> void:
	if not _enabled: return
	_poll_query(); _refresh_accum += delta
	if _refresh_accum >= refresh_interval_s:
		_refresh_accum = 0.0; _refresh_desired(false)
	_start_query_if_needed()

static func coverage_radius_for_altitude(altitude_m: float, cell_size: float, base_radius: int, max_radius: int, altitude_factor: float) -> int:
	var safe_cell_size := maxf(1.0, cell_size)
	var altitude_radius := ceili(maxf(0.0, altitude_m) * maxf(0.0, altitude_factor) / safe_cell_size) + 1
	return clampi(maxi(base_radius, altitude_radius), maxi(1, base_radius), maxi(base_radius, max_radius))

func _refresh_desired(force: bool) -> void:
	if _camera_rig == null or not _camera_rig.has_method("get_focus_world"): return
	var focus_world: Vector3 = _camera_rig.call("get_focus_world")
	var focus_abs: Vector2 = _coordinates.world_to_absolute(focus_world)
	var center := Vector2i(floori(focus_abs.x / cell_size_m), floori(focus_abs.y / cell_size_m))
	var altitude := float(_camera_rig.call("get_altitude")) if _camera_rig.has_method("get_altitude") else 0.0
	var radius := coverage_radius_for_altitude(altitude, cell_size_m, far_radius_cells, max_view_radius_cells, coverage_altitude_factor)
	var next_desired: Dictionary = {}; var candidates: Array[Dictionary] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var distance_cells := maxi(absi(dx), absi(dy)); var cell := center + Vector2i(dx, dy); var lod := MeshBuilder.LOD_NEAR
			if distance_cells > near_radius_cells or altitude >= far_lod_altitude_m: lod = MeshBuilder.LOD_FAR
			candidates.append({"cell": cell, "lod": lod, "distance": distance_cells})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["distance"]) < int(b["distance"]))
	var limit := mini(maxi(1, max_resident_cells), candidates.size())
	for i in range(limit):
		var request: Dictionary = candidates[i]; next_desired[_cell_key(request["cell"])] = int(request["lod"])
	var changed := force or next_desired.hash() != _desired.hash(); _desired = next_desired
	if changed:
		_generation += 1; _queue.clear(); _queued.clear()
		# A pure coverage contraction can retire immediately because every desired
		# replacement is already resident. During pan/zoom expansion keep the old
		# visible cells until their replacements arrive; resident-slot eviction then
		# removes stale cells incrementally without exposing a streaming hole.
		if desired_coverage_ready(_active, _desired): _retire_stale_active_cells()
	for request in candidates:
		var cell: Vector2i = request["cell"]; var key := _cell_key(cell)
		if not _desired.has(key): continue
		var wanted_lod := int(_desired[key])
		if _active.has(key) and int((_active[key] as Dictionary).get("lod", -1)) == wanted_lod: continue
		_enqueue_cell(key, wanted_lod)
	_trim_queue(); _start_query_if_needed()

static func desired_coverage_ready(active: Dictionary, desired: Dictionary) -> bool:
	for value in desired.keys():
		var key := String(value)
		if not active.has(key): return false
		if int((active[key] as Dictionary).get("lod", -1)) != int(desired[key]): return false
	return true

func _retire_stale_active_cells() -> void:
	var stale_keys: Array[String] = []
	for value in _active.keys():
		var key := String(value)
		if not _desired.has(key): stale_keys.append(key)
	for key in stale_keys: _evict_active_key(key)

func _enqueue_cell(key: String, lod: int) -> void:
	var queue_id := "%s:%d" % [key, lod]
	if _queued.has(queue_id) or _query_key == queue_id: return
	_queue.append({"key": key, "queue_id": queue_id, "cell": _parse_cell_key(key), "lod": lod, "generation": _generation}); _queued[queue_id] = true

func _trim_queue() -> void:
	while _queue.size() > maxi(1, max_pending_cells):
		var dropped: Dictionary = _queue.pop_back(); _queued.erase(String(dropped.get("queue_id", "")))

func _start_query_if_needed() -> void:
	if _query_thread != null or _queue.is_empty() or not _enabled: return
	var request: Dictionary = _queue.pop_front(); var queue_id := String(request.get("queue_id", "")); _queued.erase(queue_id); _query_key = queue_id
	var key := String(request.get("key", ""))
	if _query_cache.has(key):
		var cached: Dictionary = (_query_cache[key] as Dictionary).duplicate(true); cached["request"] = request; _perf_cache_hits += 1; _query_key = ""
		_publish_query_result(cached); _start_query_if_needed(); return
	_query_thread = Thread.new(); var error := _query_thread.start(Callable(self, "_query_worker").bind(request))
	if error != OK:
		push_error("GeoDot cell query thread failed to start: %s" % error_string(error)); _query_thread = null; _query_key = ""

func _query_worker(request: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec(); var cell: Vector2i = request["cell"]
	var top_left := Vector2(float(cell.x) * cell_size_m, float(cell.y + 1) * cell_size_m)
	var result: Dictionary = _source.query_cell(top_left, cell_size_m, max_buildings_per_cell, max_roads_per_cell)
	result["request"] = request; result["total_query_ms"] = float(Time.get_ticks_usec() - started) / 1000.0
	return result

func _poll_query() -> void:
	if _query_thread == null or _query_thread.is_alive(): return
	var value: Variant = _query_thread.wait_to_finish(); _query_thread = null; _query_key = ""
	if typeof(value) != TYPE_DICTIONARY: push_error("GeoDot cell query returned invalid data"); return
	_publish_query_result(value as Dictionary)

func _publish_query_result(result: Dictionary) -> void:
	if result.get("ok", false) != true: push_error("GeoDot cell query failed: %s" % String(result.get("error", "unknown"))); return
	var request: Dictionary = result.get("request", {}); var key := String(request.get("key", "")); var lod := int(request.get("lod", -1))
	if key.is_empty() or not _desired.has(key) or int(_desired[key]) != lod: return
	if not _query_cache.has(key):
		var query_ms := float(result.get("total_query_ms", 0.0)); _perf_query_ms += query_ms; _perf_query_max_ms = maxf(_perf_query_max_ms, query_ms); _perf_queries += 1; _cache_query_result(key, result)
	_perf_building_features += int(result.get("building_features", 0)); _perf_road_features += int(result.get("road_features", 0)); _publish_cell(request, result)

func _cache_query_result(key: String, result: Dictionary) -> void:
	var cached: Dictionary = result.duplicate(true); cached.erase("request"); _query_cache[key] = cached; _query_cache_order.erase(key); _query_cache_order.append(key)
	while _query_cache_order.size() > maxi(1, max_query_cache_cells):
		var evicted: String = _query_cache_order.pop_front(); _query_cache.erase(evicted)

func _clear_query_cache() -> void: _query_cache.clear(); _query_cache_order.clear()

func _publish_cell(request: Dictionary, result: Dictionary) -> void:
	var started := Time.get_ticks_usec(); var cell: Vector2i = request["cell"]; var key := String(request["key"]); var lod := int(request["lod"])
	var origin_abs := Vector2(float(cell.x) * cell_size_m, float(cell.y) * cell_size_m); var group := Node3D.new()
	group.name = "GeoDotCell_%d_%d_L%d" % [cell.x, cell.y, lod]; group.position = _coordinates.absolute_to_world(origin_abs); group.visible = false
	var building_mesh := MeshBuilder.build_buildings(result.get("buildings", []), origin_abs, lod)
	if building_mesh != null:
		var instance := MeshInstance3D.new(); instance.name = "Buildings"; instance.mesh = building_mesh; instance.material_override = _building_material; group.add_child(instance)
	var road_mesh := MeshBuilder.build_roads(result.get("roads", []), origin_abs, lod)
	if road_mesh != null:
		var instance := MeshInstance3D.new(); instance.name = "Roads"; instance.mesh = road_mesh; instance.position.y = 0.02; instance.material_override = _road_material; group.add_child(instance)
	if not _prepare_resident_slot(key): group.free(); push_error("GeoDot resident bound prevented publishing desired cell %s" % key); return
	if _active.has(key): _evict_active_key(key)
	add_child(group); _active[key] = {"node": group, "lod": lod, "buildings": int(result.get("building_features", 0)), "roads": int(result.get("road_features", 0))}; group.visible = true
	if desired_coverage_ready(_active, _desired): _retire_stale_active_cells()
	var build_ms := float(Time.get_ticks_usec() - started) / 1000.0; _perf_build_ms += build_ms; _perf_build_max_ms = maxf(_perf_build_max_ms, build_ms); _perf_publishes += 1

func _prepare_resident_slot(publishing_key: String) -> bool:
	if _active.has(publishing_key): return true
	while _active.size() >= maxi(1, max_resident_cells):
		var stale_key := choose_stale_eviction_key(_active, _desired, publishing_key)
		if stale_key.is_empty(): return false
		_evict_active_key(stale_key)
	return true

static func choose_stale_eviction_key(active: Dictionary, desired: Dictionary, publishing_key: String) -> String:
	var keys: Array = active.keys(); keys.sort()
	for value in keys:
		var key := String(value)
		if key != publishing_key and not desired.has(key): return key
	return ""

func _evict_active_key(key: String) -> void:
	if not _active.has(key): return
	var node: Node = (_active[key] as Dictionary).get("node")
	if node is Node3D: (node as Node3D).visible = false
	if node != null: node.queue_free()
	_active.erase(key)

func _setup_materials() -> void:
	_building_material = StandardMaterial3D.new(); _building_material.albedo_color = Color.WHITE; _building_material.vertex_color_use_as_albedo = true; _building_material.roughness = 0.92; _building_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_road_material = StandardMaterial3D.new(); _road_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; _road_material.cull_mode = BaseMaterial3D.CULL_DISABLED; _road_material.vertex_color_use_as_albedo = true; _road_material.albedo_color = Color.WHITE

func _clear_active(immediate: bool = false) -> void:
	for value in _active.values():
		var node: Node = (value as Dictionary).get("node")
		if node == null: continue
		if node is Node3D: (node as Node3D).visible = false
		if immediate: node.free()
		else: node.queue_free()
	_active.clear()

func _stale_active_count() -> int:
	var count := 0
	for key in _active.keys():
		if not _desired.has(key): count += 1
	return count

func debug_snapshot() -> Dictionary:
	return {"enabled": _enabled, "ready": _ready, "active_cells": _active.size(), "desired_cells": _desired.size(), "stale_cells": _stale_active_count(), "pending_cells": _queue.size() + (1 if _query_thread != null else 0), "query_cache_cells": _query_cache.size(), "max_resident_cells": max_resident_cells, "max_pending_cells": max_pending_cells, "max_query_cache_cells": max_query_cache_cells, "source": source_metadata()}

func consume_perf_metrics() -> Dictionary:
	var result := {"geodot_query_ms": _perf_query_ms, "geodot_query_max_ms": _perf_query_max_ms, "geodot_build_ms": _perf_build_ms, "geodot_build_max_ms": _perf_build_max_ms, "geodot_queries": _perf_queries, "geodot_cache_hits": _perf_cache_hits, "geodot_publishes": _perf_publishes, "geodot_building_features": _perf_building_features, "geodot_road_features": _perf_road_features, "geodot_active_cells": _active.size(), "geodot_stale_cells": _stale_active_count(), "geodot_pending_cells": _queue.size() + (1 if _query_thread != null else 0), "geodot_query_cache_cells": _query_cache.size()}
	_perf_query_ms = 0.0; _perf_query_max_ms = 0.0; _perf_build_ms = 0.0; _perf_build_max_ms = 0.0; _perf_queries = 0; _perf_cache_hits = 0; _perf_publishes = 0; _perf_building_features = 0; _perf_road_features = 0
	return result

func apply_render_origin_shift(delta_world: Vector3) -> void:
	for value in _active.values():
		var node: Node3D = (value as Dictionary).get("node") as Node3D
		if node != null: node.position += delta_world

static func _cell_key(cell: Vector2i) -> String: return "%d:%d" % [cell.x, cell.y]
static func _parse_cell_key(key: String) -> Vector2i:
	var parts := key.split(":"); return Vector2i(int(parts[0]), int(parts[1]))
