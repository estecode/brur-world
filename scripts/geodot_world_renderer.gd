extends Node3D
class_name GeoDotWorldRenderer

const Source = preload("res://scripts/geodot_world_source.gd")
const MeshBuilder = preload("res://scripts/geodot_world_mesh_builder.gd")
const StreamingPolicy = preload("res://scripts/geodot_streaming_policy.gd")

@export var cell_size_m := 2000.0
@export var near_radius_cells := 1
@export var far_radius_cells := 3
@export var max_view_radius_cells := 6
@export var coverage_altitude_factor := 0.72
@export var viewport_margin_cells := 1
@export var max_resident_cells := 169
@export var max_pending_cells := 64
@export var max_ready_cells := 4
@export var max_query_cache_cells := 0
@export var max_buildings_per_cell := 3000
@export var max_roads_per_cell := 2500
@export var refresh_interval_s := 0.20
@export var query_workers := 2
@export var representative_building_m := 10.0
@export var far_enter_pixels := 1.5
@export var far_exit_pixels := 2.25

var _coordinates = null
var _camera_rig: Node = null
var _source = null
var _enabled := false
var _ready := false
var _presentation_visible := true
var _refresh_accum := 0.0
var _active: Dictionary = {}
var _desired: Dictionary = {}
var _queue: Array[Dictionary] = []
var _queued: Dictionary = {}
var _ready_results: Array[Dictionary] = []
var _workers: Array[Dictionary] = []
var _generation := 0
var _far_screen_lod := false
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
	_coordinates = world_coordinates; _camera_rig = camera_rig; _source = Source.new()
	var opened: Dictionary = _source.open_dataset(gpkg_path)
	if opened.get("ok", false) != true: return opened
	_setup_materials(); _ready = true; set_enabled(true); return opened

func _exit_tree() -> void: shutdown()

func shutdown() -> void:
	_enabled = false; _ready = false; set_process(false); _generation += 1
	_queue.clear(); _queued.clear(); _ready_results.clear(); _desired.clear()
	_shutdown_query_workers(); _clear_active(true); _release_render_resources(); _release_source()
	_coordinates = null; _camera_rig = null

func _release_render_resources() -> void: _building_material = null; _road_material = null
func _release_source() -> void:
	if _source != null:
		if _source.has_method("close"): _source.close()
		_source = null

func _shutdown_query_workers() -> void:
	for worker in _workers:
		var thread: Thread = worker.get("thread") as Thread
		if thread != null and thread.is_started(): thread.wait_to_finish()
	_workers.clear()

func set_enabled(value: bool) -> void:
	_enabled = value and _ready; set_process(_enabled)
	if not _enabled:
		# Streaming can be demoted while far presentation owns the screen, but already
		# built detail remains warm. Rapid reverse zoom therefore never reconstructs a
		# city merely because its presentation LOD changed.
		_generation += 1; _queue.clear(); _queued.clear(); _ready_results.clear(); _desired.clear(); _shutdown_query_workers(); return
	_refresh_desired(true)

func set_presentation_visible(value: bool) -> void:
	_presentation_visible = value
	for entry in _active.values():
		var node := (entry as Dictionary).get("node") as Node3D
		if node != null: node.visible = value

func is_enabled() -> bool: return _enabled
func is_ready() -> bool: return _ready
func source_metadata() -> Dictionary: return _source.metadata() if _source != null else {}

func _process(delta: float) -> void:
	if not _enabled: return
	_poll_queries(); _publish_one_ready_result(); _refresh_accum += delta
	if _refresh_accum >= refresh_interval_s:
		_refresh_accum = 0.0; _refresh_desired(false)
	_start_queries_if_needed()

static func coverage_radius_for_altitude(altitude_m: float, cell_size: float, base_radius: int, max_radius: int, altitude_factor: float) -> int:
	var safe := maxf(1.0, cell_size); var radius := ceili(maxf(0.0, altitude_m) * maxf(0.0, altitude_factor) / safe) + 1
	return clampi(maxi(base_radius, radius), maxi(1, base_radius), maxi(base_radius, max_radius))

static func coverage_cell_size_for_bounds(bounds: Rect2, base_cell_size: float, margin_cells: int, max_cells: int) -> float:
	return StreamingPolicy.bounded_cell_size_for_bounds(bounds, base_cell_size, margin_cells, max_cells)

static func coverage_cells_for_bounds(bounds: Rect2, size: float, margin: int, max_cells: int, focus_abs: Vector2) -> Array[Vector2i]:
	var safe := maxf(1.0, size); var cell_range: Rect2i = StreamingPolicy.cell_range_for_bounds(bounds, safe, margin)
	var min_cell := cell_range.position; var max_cell := cell_range.position + cell_range.size - Vector2i.ONE
	var focus_cell := Vector2i(floori(focus_abs.x / safe), floori(focus_abs.y / safe)); var candidates: Array[Dictionary] = []
	for y in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			var cell := Vector2i(x, y); var delta := cell - focus_cell
			candidates.append({"cell": cell, "distance": maxi(absi(delta.x), absi(delta.y)), "distance_sq": delta.length_squared()})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.distance) != int(b.distance): return int(a.distance) < int(b.distance)
		if int(a.distance_sq) != int(b.distance_sq): return int(a.distance_sq) < int(b.distance_sq)
		var ac: Vector2i = a.cell; var bc: Vector2i = b.cell; return ac.y < bc.y or (ac.y == bc.y and ac.x < bc.x))
	var result: Array[Vector2i] = []
	for i in range(mini(maxi(1, max_cells), candidates.size())): result.append(candidates[i].cell)
	return result

func _view_world_points(focus_world: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = []
	if _camera_rig.has_method("get_ground_view_corners"):
		var corners: Variant = _camera_rig.call("get_ground_view_corners")
		if typeof(corners) == TYPE_PACKED_VECTOR3_ARRAY or typeof(corners) == TYPE_ARRAY:
			for value in corners:
				if typeof(value) == TYPE_VECTOR3 and (value as Vector3).is_finite(): points.append(value)
	if not points.is_empty() and _camera_rig.has_method("is_driving_view") and bool(_camera_rig.call("is_driving_view")):
		var radius := float(_camera_rig.call("get_streaming_ground_radius_m")) if _camera_rig.has_method("get_streaming_ground_radius_m") else 0.0
		if radius > 0.0: points = [focus_world + Vector3(-radius,0,-radius), focus_world + Vector3(radius,0,-radius), focus_world + Vector3(radius,0,radius), focus_world + Vector3(-radius,0,radius)]
	if points.is_empty(): points.append(focus_world)
	return points

func _view_absolute_bounds(focus_world: Vector3) -> Rect2:
	var points := _view_world_points(focus_world); var first: Vector2 = _coordinates.world_to_absolute(points[0])
	var min_x := first.x; var max_x := first.x; var min_y := first.y; var max_y := first.y
	for i in range(1, points.size()):
		var p: Vector2 = _coordinates.world_to_absolute(points[i]); min_x = minf(min_x,p.x); max_x = maxf(max_x,p.x); min_y = minf(min_y,p.y); max_y = maxf(max_y,p.y)
	return Rect2(Vector2(min_x,min_y), Vector2(max_x-min_x,max_y-min_y))

static func projected_pixels_for_size(world_size_m: float, bounds: Rect2, viewport_size: Vector2) -> float:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0: return INF
	var meters_per_pixel := maxf(bounds.size.x / viewport_size.x, bounds.size.y / viewport_size.y)
	return world_size_m / maxf(0.0001, meters_per_pixel)

static func choose_screen_lod(was_far: bool, projected_pixels: float, enter_far_px: float, exit_far_px: float) -> int:
	if was_far: return MeshBuilder.LOD_NEAR if projected_pixels >= exit_far_px else MeshBuilder.LOD_FAR
	return MeshBuilder.LOD_FAR if projected_pixels <= enter_far_px else MeshBuilder.LOD_NEAR

func _refresh_desired(force: bool) -> void:
	if _camera_rig == null or not _camera_rig.has_method("get_focus_world"): return
	var focus_world: Vector3 = _camera_rig.call("get_focus_world"); var focus_abs: Vector2 = _coordinates.world_to_absolute(focus_world)
	var bounds := _view_absolute_bounds(focus_world); var query_size := coverage_cell_size_for_bounds(bounds, cell_size_m, viewport_margin_cells, max_resident_cells)
	var cells := coverage_cells_for_bounds(bounds, query_size, viewport_margin_cells, max_resident_cells, focus_abs)
	var viewport_size := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1920,1080)
	var projected_px := projected_pixels_for_size(representative_building_m, bounds, viewport_size)
	var screen_lod := choose_screen_lod(_far_screen_lod, projected_px, far_enter_pixels, far_exit_pixels); _far_screen_lod = screen_lod == MeshBuilder.LOD_FAR
	var next_desired: Dictionary = {}; var candidates: Array[Dictionary] = []
	for cell in cells:
		var key := _cell_key(cell, query_size); var request := {"key":key,"cell":cell,"cell_size_m":query_size,"lod":screen_lod}
		next_desired[key] = screen_lod; candidates.append(request)
	var changed := force or next_desired.hash() != _desired.hash(); _desired = next_desired
	if changed:
		_generation += 1; _queue.clear(); _queued.clear(); _drop_obsolete_ready_results()
		if desired_coverage_ready(_active,_desired): _retire_stale_active_cells()
	for request in candidates:
		var key := String(request.key); var lod := int(request.lod)
		if _active.has(key) and int((_active[key] as Dictionary).get("lod",-1)) == lod: continue
		_enqueue_request(request)
	_trim_queue(); _start_queries_if_needed()

static func desired_coverage_ready(active: Dictionary, desired: Dictionary) -> bool:
	if desired.is_empty(): return false
	for value in desired.keys():
		var key := String(value)
		if not active.has(key) or int((active[key] as Dictionary).get("lod",-1)) != int(desired[key]): return false
	return true

func _retire_stale_active_cells() -> void:
	# Stale cells are a warm cache, not immediate garbage. They are evicted only
	# when a new resident needs the bounded slot.
	return

func _enqueue_request(request: Dictionary) -> void:
	var queue_id := "%s:%d" % [String(request.key), int(request.lod)]
	if _queued.has(queue_id) or _worker_has_queue_id(queue_id): return
	request.queue_id = queue_id; request.generation = _generation; _queue.append(request); _queued[queue_id] = true

func _worker_has_queue_id(queue_id: String) -> bool:
	for worker in _workers:
		if String(worker.get("queue_id","")) == queue_id: return true
	return false

func _trim_queue() -> void:
	while _queue.size() > maxi(1,max_pending_cells):
		var dropped: Dictionary = _queue.pop_back(); _queued.erase(String(dropped.get("queue_id","")))

func _start_queries_if_needed() -> void:
	while _workers.size() < maxi(1,query_workers) and not _queue.is_empty() and _enabled and _ready_results.size() < maxi(1,max_ready_cells):
		var request: Dictionary = _queue.pop_front(); _queued.erase(String(request.queue_id))
		var thread := Thread.new(); var error := thread.start(Callable(self,"_query_worker").bind(request))
		if error != OK: push_error("GeoDot cell query thread failed: %s" % error_string(error)); continue
		_workers.append({"thread":thread,"queue_id":String(request.queue_id)})

func _query_worker(request: Dictionary) -> Dictionary:
	var started := Time.get_ticks_usec(); var cell: Vector2i = request.cell; var size := float(request.cell_size_m)
	var result: Dictionary = _source.query_cell(Vector2(float(cell.x)*size,float(cell.y+1)*size),size,max_buildings_per_cell,max_roads_per_cell)
	result.request = request; result.total_query_ms = float(Time.get_ticks_usec()-started)/1000.0; return result

func _poll_queries() -> void:
	var finished: Array[int] = []
	for i in range(_workers.size()):
		var thread: Thread = _workers[i].thread as Thread
		if thread == null or not thread.is_alive(): finished.append(i)
	for r in range(finished.size()-1,-1,-1):
		var i := finished[r]; var worker: Dictionary = _workers[i]; _workers.remove_at(i); var thread: Thread = worker.thread as Thread
		if thread == null: continue
		var value: Variant = thread.wait_to_finish()
		if typeof(value) != TYPE_DICTIONARY: continue
		var result: Dictionary = value; var request: Dictionary = result.get("request",{})
		if int(request.get("generation",-1)) != _generation: continue
		if _ready_results.size() < maxi(1,max_ready_cells): _ready_results.append(result)

func _drop_obsolete_ready_results() -> void:
	var kept: Array[Dictionary] = []
	for result in _ready_results:
		var request: Dictionary = result.get("request",{}); var key := String(request.get("key","")); var lod := int(request.get("lod",-1))
		if int(request.get("generation",-1)) == _generation and _desired.has(key) and int(_desired[key]) == lod: kept.append(result)
	_ready_results = kept

func _publish_one_ready_result() -> void:
	if _ready_results.is_empty(): return
	var result: Dictionary = _ready_results.pop_front(); var request: Dictionary = result.get("request",{}); var key := String(request.get("key","")); var lod := int(request.get("lod",-1))
	if int(request.get("generation",-1)) != _generation or not _desired.has(key) or int(_desired[key]) != lod: return
	if result.get("ok",false) != true: push_error("GeoDot query failed: %s" % String(result.get("error","unknown"))); return
	var query_ms := float(result.get("total_query_ms",0.0)); _perf_query_ms += query_ms; _perf_query_max_ms = maxf(_perf_query_max_ms,query_ms); _perf_queries += 1
	_perf_building_features += int(result.get("building_features",0)); _perf_road_features += int(result.get("road_features",0)); _publish_cell(request,result)

func _publish_cell(request: Dictionary, result: Dictionary) -> void:
	var started := Time.get_ticks_usec(); var cell: Vector2i = request.cell; var key := String(request.key); var lod := int(request.lod); var size := float(request.cell_size_m)
	var origin := Vector2(float(cell.x)*size,float(cell.y)*size); var group := Node3D.new(); group.name = "GeoDotCell_%d_%d_L%d" % [cell.x,cell.y,lod]; group.position = _coordinates.absolute_to_world(origin); group.visible = false
	var buildings := MeshBuilder.build_buildings(result.get("buildings",[]),origin,lod)
	if buildings != null:
		var instance := MeshInstance3D.new(); instance.name="Buildings"; instance.mesh=buildings; instance.material_override=_building_material; group.add_child(instance)
	var roads := MeshBuilder.build_roads(result.get("roads",[]),origin,lod)
	if roads != null:
		var instance := MeshInstance3D.new(); instance.name="Roads"; instance.mesh=roads; instance.position.y=0.02; instance.material_override=_road_material; group.add_child(instance)
	if not _prepare_resident_slot(key): group.free(); return
	if _active.has(key): _evict_active_key(key)
	add_child(group); _active[key]={"node":group,"lod":lod,"buildings":int(result.get("building_features",0)),"roads":int(result.get("road_features",0))}; group.visible=_presentation_visible
	var build_ms := float(Time.get_ticks_usec()-started)/1000.0; _perf_build_ms += build_ms; _perf_build_max_ms=maxf(_perf_build_max_ms,build_ms); _perf_publishes += 1

func _prepare_resident_slot(key: String) -> bool:
	if _active.has(key): return true
	while _active.size() >= maxi(1,max_resident_cells):
		var stale := choose_stale_eviction_key(_active,_desired,key)
		if stale.is_empty(): return false
		_evict_active_key(stale)
	return true

static func choose_stale_eviction_key(active: Dictionary, desired: Dictionary, publishing_key: String) -> String:
	var keys := active.keys(); keys.sort()
	for value in keys:
		var key := String(value)
		if key != publishing_key and not desired.has(key): return key
	return ""

func _evict_active_key(key: String) -> void:
	if not _active.has(key): return
	var node: Node = (_active[key] as Dictionary).get("node"); _active.erase(key)
	if node != null:
		if node is Node3D: (node as Node3D).visible=false
		node.free()

func _setup_materials() -> void:
	_building_material=StandardMaterial3D.new(); _building_material.albedo_color=Color.WHITE; _building_material.vertex_color_use_as_albedo=true; _building_material.roughness=0.92; _building_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	_road_material=StandardMaterial3D.new(); _road_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; _road_material.cull_mode=BaseMaterial3D.CULL_DISABLED; _road_material.vertex_color_use_as_albedo=true; _road_material.albedo_color=Color.WHITE

func _clear_active(immediate: bool=false) -> void:
	for value in _active.values():
		var node: Node = (value as Dictionary).get("node")
		if node != null:
			if node is Node3D: (node as Node3D).visible=false
			if immediate: node.free()
			else: node.queue_free()
	_active.clear()

func _stale_active_count() -> int:
	var count := 0
	for key in _active.keys():
		if not _desired.has(key): count += 1
	return count

func debug_snapshot() -> Dictionary:
	return {"enabled":_enabled,"ready":_ready,"presentation_visible":_presentation_visible,"active_cells":_active.size(),"desired_cells":_desired.size(),"stale_cells":_stale_active_count(),"pending_cells":_queue.size()+_workers.size(),"ready_cells":_ready_results.size(),"query_workers":_workers.size(),"query_cache_cells":0,"screen_lod":"far" if _far_screen_lod else "near","max_resident_cells":max_resident_cells,"max_pending_cells":max_pending_cells,"max_ready_cells":max_ready_cells,"source":source_metadata()}

func consume_perf_metrics() -> Dictionary:
	var result := {"renderer":"geodot","geodot_query_ms":_perf_query_ms,"geodot_query_max_ms":_perf_query_max_ms,"geodot_build_ms":_perf_build_ms,"geodot_build_max_ms":_perf_build_max_ms,"geodot_queries":_perf_queries,"geodot_publishes":_perf_publishes,"geodot_building_features":_perf_building_features,"geodot_road_features":_perf_road_features,"geodot_active_cells":_active.size(),"geodot_stale_cells":_stale_active_count(),"geodot_pending_cells":_queue.size()+_workers.size(),"geodot_ready_cells":_ready_results.size(),"geodot_workers":_workers.size(),"geodot_query_cache_cells":0,"geodot_screen_lod":"far" if _far_screen_lod else "near"}
	_perf_query_ms=0.0; _perf_query_max_ms=0.0; _perf_build_ms=0.0; _perf_build_max_ms=0.0; _perf_queries=0; _perf_publishes=0; _perf_building_features=0; _perf_road_features=0; return result

func apply_render_origin_shift(delta_world: Vector3) -> void:
	for value in _active.values():
		var node: Node3D = (value as Dictionary).get("node") as Node3D
		if node != null: node.position += delta_world

static func _cell_key(cell: Vector2i, query_cell_size: float=0.0) -> String:
	if query_cell_size <= 0.0: return "%d:%d" % [cell.x,cell.y]
	return "%.3f:%d:%d" % [query_cell_size,cell.x,cell.y]
