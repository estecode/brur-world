extends Node3D
class_name GeoDotWorldRenderer

const Source = preload("res://scripts/geodot_world_source.gd")
const MeshBuilder = preload("res://scripts/geodot_world_mesh_builder.gd")
const StreamingPolicy = preload("res://scripts/geodot_streaming_policy.gd")
signal coverage_changed

@export var cell_size_m := 2000.0
@export var viewport_margin_cells := 1
@export var max_resident_cells := 169
@export var max_pending_cells := 64
@export var max_ready_cells := 4
@export var max_buildings_per_cell := 3000
@export var max_roads_per_cell := 2500
@export var refresh_interval_s := 0.20
@export var query_workers := 2
@export var representative_building_m := 10.0
@export var far_enter_pixels := 1.5
@export var far_exit_pixels := 2.25
var _coordinates=null; var _camera_rig:Node=null; var _source=null
var _enabled:=false; var _streaming_enabled:=true; var _ready:=false; var _presentation_visible:=true; var _refresh_accum:=0.0
var _active:Dictionary={}; var _warm:Dictionary={}; var _desired:Dictionary={}; var _queue:Array[Dictionary]=[]; var _queued:Dictionary={}; var _ready_results:Array[Dictionary]=[]; var _workers:Array[Dictionary]=[]; var _generation:=0; var _far_screen_lod:=false
var _building_material:StandardMaterial3D=null; var _road_material:StandardMaterial3D=null

func setup(world_coordinates,camera_rig:Node,gpkg_path:String)->Dictionary:
	assert(world_coordinates!=null);assert(camera_rig!=null);_coordinates=world_coordinates;_camera_rig=camera_rig;_source=Source.new();var opened:Dictionary=_source.open_dataset(gpkg_path)
	if opened.get("ok",false)!=true:return opened
	_setup_materials();_ready=true;set_enabled(true);return opened
func _exit_tree()->void:shutdown()
func shutdown()->void:
	_enabled=false;_streaming_enabled=false;_ready=false;set_process(false);_generation+=1;_queue.clear();_queued.clear();_ready_results.clear();_desired.clear();_shutdown_query_workers();_clear_active(true);_clear_warm(true);_building_material=null;_road_material=null
	if _source!=null:
		if _source.has_method("close"):_source.close()
		_source=null
	_coordinates=null;_camera_rig=null
func _shutdown_query_workers()->void:
	for worker in _workers:
		var thread:Thread=worker.get("thread") as Thread
		if thread!=null and thread.is_started():thread.wait_to_finish()
	_workers.clear()
func set_enabled(value:bool)->void:
	_enabled=value and _ready;set_process(_enabled)
	if not _enabled:_streaming_enabled=false;_generation+=1;_queue.clear();_queued.clear();_ready_results.clear();_desired.clear();_shutdown_query_workers();return
	_streaming_enabled=true;_refresh_desired(true)
func set_streaming_enabled(value:bool)->void:
	var next:=value and _enabled and _ready
	if next==_streaming_enabled:return
	_streaming_enabled=next
	if not _streaming_enabled:
		_generation+=1;_queue.clear();_queued.clear();_ready_results.clear();_desired.clear();_trim_active_to_budget();coverage_changed.emit();return
	_refresh_desired(true)
func set_presentation_visible(value:bool)->void:
	_presentation_visible=value
	for entry in _active.values():
		var node:Node3D=(entry as Dictionary).get("node") as Node3D
		if node!=null:node.visible=value
func is_enabled()->bool:return _enabled
func is_ready()->bool:return _ready
func source_metadata()->Dictionary:return _source.metadata() if _source!=null else {}
func _process(delta:float)->void:
	if not _enabled:return
	_poll_queries()
	if _streaming_enabled:_publish_one_ready_result();_refresh_accum+=delta
	if _streaming_enabled and _refresh_accum>=refresh_interval_s:_refresh_accum=0.0;_refresh_desired(false)
	if _streaming_enabled:_start_queries_if_needed()
static func coverage_cell_size_for_bounds(_bounds:Rect2,base_cell_size:float,_margin_cells:int,_max_cells:int)->float:return maxf(1.0,base_cell_size)
static func coverage_cells_for_bounds(bounds:Rect2,size:float,margin:int,max_cells:int,focus_abs:Vector2)->Array[Vector2i]:
	var safe:=maxf(1.0,size);var cr:Rect2i=StreamingPolicy.cell_range_for_bounds(bounds,safe,margin);var minc:=cr.position;var maxc:=cr.position+cr.size-Vector2i.ONE;var fc:=Vector2i(floori(focus_abs.x/safe),floori(focus_abs.y/safe));var cands:Array[Dictionary]=[]
	for y in range(minc.y,maxc.y+1):
		for x in range(minc.x,maxc.x+1):var c:=Vector2i(x,y);var d:=c-fc;cands.append({"cell":c,"distance":maxi(absi(d.x),absi(d.y)),"distance_sq":d.length_squared()})
	cands.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return int(a.distance)<int(b.distance) if int(a.distance)!=int(b.distance) else (int(a.distance_sq)<int(b.distance_sq) if int(a.distance_sq)!=int(b.distance_sq) else ((a.cell as Vector2i).y<(b.cell as Vector2i).y or ((a.cell as Vector2i).y==(b.cell as Vector2i).y and (a.cell as Vector2i).x<(b.cell as Vector2i).x))))
	var out:Array[Vector2i]=[];for i in range(mini(maxi(1,max_cells),cands.size())):out.append(cands[i].cell);return out
func _view_world_points(focus:Vector3)->Array[Vector3]:
	var p:Array[Vector3]=[]
	if _camera_rig.has_method("get_ground_view_corners"):
		var corners:Variant=_camera_rig.call("get_ground_view_corners")
		if typeof(corners)==TYPE_PACKED_VECTOR3_ARRAY or typeof(corners)==TYPE_ARRAY:
			for v in corners:if typeof(v)==TYPE_VECTOR3 and (v as Vector3).is_finite():p.append(v)
	if p.is_empty():p.append(focus)
	return p
func _view_absolute_bounds(focus:Vector3)->Rect2:
	var pts:=_view_world_points(focus);var f:Vector2=_coordinates.world_to_absolute(pts[0]);var mn:=f;var mx:=f
	for i in range(1,pts.size()):var q:Vector2=_coordinates.world_to_absolute(pts[i]);mn.x=minf(mn.x,q.x);mn.y=minf(mn.y,q.y);mx.x=maxf(mx.x,q.x);mx.y=maxf(mx.y,q.y)
	return Rect2(mn,mx-mn)
static func projected_pixels_for_size(world_size_m:float,bounds:Rect2,viewport_size:Vector2)->float:
	if viewport_size.x<=0.0 or viewport_size.y<=0.0:return INF
	return world_size_m/maxf(0.0001,maxf(bounds.size.x/viewport_size.x,bounds.size.y/viewport_size.y))
static func choose_screen_lod(was_far:bool,pixels:float,enter:float,exit:float)->int:
	if was_far:return MeshBuilder.LOD_NEAR if pixels>=exit else MeshBuilder.LOD_FAR
	return MeshBuilder.LOD_FAR if pixels<=enter else MeshBuilder.LOD_NEAR
func _refresh_desired(force:bool)->void:
	if not _streaming_enabled or _camera_rig==null or not _camera_rig.has_method("get_focus_world"):return
	var focus:Vector3=_camera_rig.call("get_focus_world");var abs:Vector2=_coordinates.world_to_absolute(focus);var bounds:=_view_absolute_bounds(focus);var size:=coverage_cell_size_for_bounds(bounds,cell_size_m,viewport_margin_cells,max_resident_cells);var cells:=coverage_cells_for_bounds(bounds,size,viewport_margin_cells,max_resident_cells,abs);var vp:=get_viewport().get_visible_rect().size if get_viewport()!=null else Vector2(1920,1080);var px:=projected_pixels_for_size(representative_building_m,bounds,vp);var lod:=choose_screen_lod(_far_screen_lod,px,far_enter_pixels,far_exit_pixels);_far_screen_lod=lod==MeshBuilder.LOD_FAR;var next:Dictionary={};var candidates:Array[Dictionary]=[]
	for cell in cells:var key:=_cell_key(cell,size);next[key]=lod;candidates.append({"key":key,"cell":cell,"cell_size_m":size,"lod":lod})
	var changed:=force or next.hash()!=_desired.hash();_desired=next
	if changed:_generation+=1;_queue.clear();_queued.clear();_drop_obsolete_ready_results();_park_obsolete_active()
	for request in candidates:
		var key:=String(request.key);if _active.has(key) and int((_active[key] as Dictionary).get("lod",-1))==lod:continue
		if _restore_warm(key,lod):continue
		_enqueue_request(request)
	_trim_queue();_trim_warm();_trim_active_to_budget();_start_queries_if_needed()
func _park_obsolete_active()->void:
	var keys:=_active.keys()
	for value in keys:
		var key:=String(value)
		if not _desired.has(key):_park_warm(key)
func _active_coverage_rects()->Array[Rect2]:
	var out:Array[Rect2]=[]
	if not _streaming_enabled:return out
	for e_value in _active.values():
		var e:Dictionary=e_value;var o:Vector2=e.get("origin_abs",Vector2.ZERO);var s:=float(e.get("cell_size_m",0.0));if s>0.0:out.append(Rect2(o,Vector2(s,s)))
	return out
static func desired_coverage_ready(active:Dictionary,desired:Dictionary)->bool:
	if desired.is_empty():return false
	for v in desired.keys():var k:=String(v);if not active.has(k):return false
	return true
func _enqueue_request(request:Dictionary)->void:
	var id:="%s:%d"%[String(request.key),int(request.lod)];if _queued.has(id) or _worker_has_queue_id(id):return
	request.queue_id=id;request.generation=_generation;_queue.append(request);_queued[id]=true
func _worker_has_queue_id(id:String)->bool:
	for w in _workers:if String(w.get("queue_id",""))==id:return true
	return false
func _trim_queue()->void:
	while _queue.size()>maxi(1,max_pending_cells):var d:Dictionary=_queue.pop_back();_queued.erase(String(d.get("queue_id","")))
func _start_queries_if_needed()->void:
	while _workers.size()<maxi(1,query_workers) and not _queue.is_empty() and _enabled and _streaming_enabled and _ready_results.size()<maxi(1,max_ready_cells):var r:Dictionary=_queue.pop_front();_queued.erase(String(r.queue_id));var t:=Thread.new();if t.start(Callable(self,"_query_worker").bind(r))==OK:_workers.append({"thread":t,"queue_id":String(r.queue_id)})
func _query_worker(request:Dictionary)->Dictionary:
	var started:=Time.get_ticks_usec();var cell:Vector2i=request.cell;var size:=float(request.cell_size_m);var result:Dictionary=_source.query_cell(Vector2(float(cell.x)*size,float(cell.y+1)*size),size,max_buildings_per_cell,max_roads_per_cell);result.request=request;result.total_query_ms=float(Time.get_ticks_usec()-started)/1000.0;return result
func _poll_queries()->void:
	var done:Array[int]=[];for i in range(_workers.size()):var t:Thread=_workers[i].thread as Thread;if t==null or not t.is_alive():done.append(i)
	for r in range(done.size()-1,-1,-1):var i:=done[r];var w:Dictionary=_workers[i];_workers.remove_at(i);var t:Thread=w.thread as Thread;if t==null:continue;var v:Variant=t.wait_to_finish();if typeof(v)!=TYPE_DICTIONARY:continue;var result:Dictionary=v;var req:Dictionary=result.get("request",{});if _streaming_enabled and int(req.get("generation",-1))==_generation and _ready_results.size()<maxi(1,max_ready_cells):_ready_results.append(result)
func _drop_obsolete_ready_results()->void:
	var kept:Array[Dictionary]=[]
	for result in _ready_results:
		var req:Dictionary=result.get("request",{});var key:=String(req.get("key",""));if int(req.get("generation",-1))==_generation and _desired.has(key) and int(_desired[key])==int(req.get("lod",-1)):kept.append(result)
	_ready_results=kept
func _publish_one_ready_result()->void:
	if _ready_results.is_empty():return
	var result:Dictionary=_ready_results.pop_front();var req:Dictionary=result.get("request",{});var key:=String(req.get("key",""));var lod:=int(req.get("lod",-1));if int(req.get("generation",-1))!=_generation or not _desired.has(key) or int(_desired[key])!=lod:return
	if result.get("ok",false)!=true:return
	_publish_cell(req,result)
func _publish_cell(request:Dictionary,result:Dictionary)->void:
	var cell:Vector2i=request.cell;var key:=String(request.key);var lod:=int(request.lod);var size:=float(request.cell_size_m);var origin:=Vector2(float(cell.x)*size,float(cell.y)*size);var group:=Node3D.new();group.position=_coordinates.absolute_to_world(origin);group.visible=false
	var buildings:=MeshBuilder.build_buildings(result.get("buildings",[]),origin,lod);if buildings!=null:var bi:=MeshInstance3D.new();bi.mesh=buildings;bi.material_override=_building_material;group.add_child(bi)
	var roads:=MeshBuilder.build_roads(result.get("roads",[]),origin,lod);if roads!=null:var ri:=MeshInstance3D.new();ri.mesh=roads;ri.material_override=_road_material;group.add_child(ri)
	if not _prepare_resident_slot(key):group.free();return
	if _active.has(key):_park_warm(key)
	add_child(group);_active[key]={"node":group,"lod":lod,"origin_abs":origin,"cell_size_m":size,"buildings":int(result.get("building_features",0)),"warm_tick":Time.get_ticks_msec()};group.visible=_presentation_visible;coverage_changed.emit()
func _warm_key(key:String,lod:int)->String:return "%s:%d"%[key,lod]
func _park_warm(key:String)->void:
	if not _active.has(key):return
	var entry:Dictionary=_active[key];_active.erase(key);var node:Node3D=entry.get("node") as Node3D
	if node!=null:node.visible=false
	entry["warm_tick"]=Time.get_ticks_msec();var wk:=_warm_key(key,int(entry.get("lod",-1)))
	if _warm.has(wk):var old:Node=(_warm[wk] as Dictionary).get("node") as Node;if old!=null:old.free()
	_warm[wk]=entry
func _restore_warm(key:String,lod:int)->bool:
	var wk:=_warm_key(key,lod);if not _warm.has(wk):return false
	if _active.has(key):_park_warm(key)
	var entry:Dictionary=_warm[wk];_warm.erase(wk);_active[key]=entry;var node:Node3D=entry.get("node") as Node3D;if node!=null:node.visible=_presentation_visible
	coverage_changed.emit();return true
func _trim_warm()->void:
	var cap:=maxi(4,max_resident_cells/4)
	while _warm.size()>cap:
		var oldest:="";var tick:=9223372036854775807
		for k in _warm.keys():var e:Dictionary=_warm[k];var t:=int(e.get("warm_tick",0));if t<tick:tick=t;oldest=String(k)
		if oldest.is_empty():break
		var node:Node=(_warm[oldest] as Dictionary).get("node") as Node;_warm.erase(oldest);if node!=null:node.free()
func _trim_active_to_budget()->void:
	while _active.size()>maxi(1,max_resident_cells):
		var keys:=_active.keys();keys.sort();var key:=String(keys[0]);_evict_active_key(key,false)
func evict_warm_for_pressure(target_bytes:int=0)->void:
	var _unused:=target_bytes
	_clear_warm(true)
	if not _streaming_enabled:_clear_active(true)
func _prepare_resident_slot(key:String)->bool:
	if _active.has(key):return true
	while _active.size()>=maxi(1,max_resident_cells):var stale:=choose_stale_eviction_key(_active,_desired,key);if stale.is_empty():return false;_evict_active_key(stale)
	return true
static func choose_stale_eviction_key(active:Dictionary,desired:Dictionary,publishing_key:String)->String:
	var keys:=active.keys();keys.sort();for v in keys:var k:=String(v);if k!=publishing_key and not desired.has(k):return k
	return ""
func _evict_active_key(key:String,notify:bool=true)->void:
	if not _active.has(key):return
	var node:Node=(_active[key] as Dictionary).get("node");_active.erase(key);if node!=null:node.free()
	if notify:coverage_changed.emit()
func _setup_materials()->void:
	_building_material=StandardMaterial3D.new();_building_material.albedo_color=Color.WHITE;_building_material.vertex_color_use_as_albedo=true;_building_material.roughness=0.92;_building_material.cull_mode=BaseMaterial3D.CULL_DISABLED;_road_material=StandardMaterial3D.new();_road_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;_road_material.vertex_color_use_as_albedo=true
func _clear_active(immediate:bool=false)->void:
	for v in _active.values():var n:Node=(v as Dictionary).get("node");if n!=null:if immediate:n.free();else:n.queue_free()
	_active.clear();coverage_changed.emit()
func _clear_warm(immediate:bool=false)->void:
	for v in _warm.values():var n:Node=(v as Dictionary).get("node");if n!=null:if immediate:n.free();else:n.queue_free()
	_warm.clear()
func ready_coverage_rects()->Array[Rect2]:return _active_coverage_rects()
func debug_snapshot()->Dictionary:return {"enabled":_enabled,"streaming_enabled":_streaming_enabled,"ready":_ready,"presentation_visible":_presentation_visible,"active_cells":_active.size(),"warm_cells":_warm.size(),"desired_cells":_desired.size(),"ready_desired_cells":ready_coverage_rects().size(),"desired_lod_ready":desired_coverage_ready(_active,_desired),"pending_cells":_queue.size()+_workers.size(),"ready_cells":_ready_results.size(),"screen_lod":"far" if _far_screen_lod else "near","max_resident_cells":max_resident_cells,"stable_cell_size_m":cell_size_m,"source":source_metadata()}
func consume_perf_metrics()->Dictionary:return {"renderer":"geodot","geodot_active_cells":_active.size(),"geodot_warm_cells":_warm.size(),"geodot_pending_cells":_queue.size()+_workers.size()}
func apply_render_origin_shift(delta_world:Vector3)->void:
	for v in _active.values():var n:Node3D=(v as Dictionary).get("node") as Node3D;if n!=null:n.position+=delta_world
	for v in _warm.values():var n:Node3D=(v as Dictionary).get("node") as Node3D;if n!=null:n.position+=delta_world
static func _cell_key(cell:Vector2i,query_cell_size:float=0.0)->String:return "%d:%d"%[cell.x,cell.y] if query_cell_size<=0.0 else "%.3f:%d:%d"%[query_cell_size,cell.x,cell.y]