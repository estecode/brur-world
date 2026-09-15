extends Node3D
class_name GeoDotFarRenderer
const FarCache=preload("res://scripts/geodot_far_cache.gd")
const LodPolicy=preload("res://scripts/geodot_lod_policy.gd")
@export var enter_distance_m:=55000.0
@export var exit_distance_m:=50000.0
@export var target_screen_cell_px:=5.0
@export var base_sample_budget:=12000
@export var hard_sample_cap:=24000
@export var density_scale:=1.0
var ram_target_bytes:=2048*1024*1024;var ram_hard_bytes:=2560*1024*1024
var _coordinates=null;var _camera_rig:Node=null;var _detail_provider:Node=null;var _cache=FarCache.new();var _instance:MultiMeshInstance3D=null;var _quad:QuadMesh=null;var _material:StandardMaterial3D=null;var _enabled:=false;var _refresh_accum:=0.25;var _last_samples:=0;var _last_level:=-1;var _last_cell_m:=0.0;var _last_mpp:=0.0;var _last_build_ms:=0.0;var _last_pressure:=0.0;var _last_signature:="";var _masked_samples:=0
func setup(world_coordinates,camera_rig:Node,cache_path:String)->Dictionary:
	_coordinates=world_coordinates;_camera_rig=camera_rig;var opened:=_cache.open(cache_path);if opened.get("ok",false)!=true:return opened
	_material=StandardMaterial3D.new();_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;_material.albedo_color=Color(0.32,0.33,0.34,0.72);_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;_material.cull_mode=BaseMaterial3D.CULL_DISABLED;_quad=QuadMesh.new();_quad.orientation=PlaneMesh.FACE_Y;_quad.size=Vector2.ONE;_quad.material=_material;_instance=MultiMeshInstance3D.new();_instance.name="GeoDotFarSpatialFallback";add_child(_instance);_enabled=true;set_process(true);return opened
func set_detail_provider(provider:Node)->void:_detail_provider=provider;_last_signature=""
func shutdown()->void:
	set_process(false);_enabled=false;_cache.close();if _instance!=null:_instance.free();_instance=null;_quad=null;_material=null;_coordinates=null;_camera_rig=null;_detail_provider=null
func _exit_tree()->void:shutdown()
# Legacy calls are deliberately harmless: ownership is now spatial, not global.
func set_detail_owner(_value:bool)->void:pass
func set_transition_hold(_value:bool)->void:pass
func set_tuning(values:Dictionary)->void:
	if values.has("far_density"):density_scale=clampf(float(values.far_density),0.05,4.0)
	if values.has("far_pixel_budget"):base_sample_budget=clampi(int(values.far_pixel_budget),500,hard_sample_cap)
	if values.has("far_tile_pixels"):target_screen_cell_px=clampf(float(values.far_tile_pixels),1.0,32.0)
	if values.has("ram_target_mb"):ram_target_bytes=maxi(256,int(values.ram_target_mb))*1024*1024
	if values.has("ram_hard_mb"):ram_hard_bytes=maxi(int(values.get("ram_target_mb",2048)),int(values.ram_hard_mb))*1024*1024
	_last_signature=""
func _process(delta:float)->void:
	if not _enabled or _camera_rig==null:return
	_refresh_accum+=delta;if _refresh_accum<0.10:return
	_refresh_accum=0.0;_refresh()
func _refresh()->void:
	if not _camera_rig.has_method("get_focus_world"):return
	var focus:Vector3=_camera_rig.call("get_focus_world");var camera:=get_viewport().get_camera_3d() if get_viewport()!=null else null;if camera==null:return
	var distance:=camera.global_position.distance_to(focus);var bounds:=_view_bounds(focus,distance);var viewport:=get_viewport().get_visible_rect().size;_last_mpp=LodPolicy.meters_per_pixel(bounds,viewport);var level:=_cache.choose_level(maxf(2000.0,_last_mpp*target_screen_cell_px));if level<0:return
	_last_pressure=_renderer_memory_pressure();var budget:=LodPolicy.sample_budget(base_sample_budget,density_scale*LodPolicy.quality_scale_for_pressure(_last_pressure),hard_sample_cap);var cell_m:=_cache.level_cell_size(level);var qmin:=Vector2(floor(bounds.position.x/cell_m),floor(bounds.position.y/cell_m));var qmax:=Vector2(ceil(bounds.end.x/cell_m),ceil(bounds.end.y/cell_m));var coverage:=_ready_detail_coverage();var signature:="%d:%d:%d:%d:%d:%d:%d"%[level,int(qmin.x),int(qmin.y),int(qmax.x),int(qmax.y),budget,coverage.hash()];if signature==_last_signature:return
	var started:=Time.get_ticks_usec();var samples:=_cache.query_bounds(bounds,level,budget,density_scale);_publish(samples,coverage);_last_signature=signature;_last_level=level;_last_samples=samples.size();_last_build_ms=float(Time.get_ticks_usec()-started)/1000.0;if not samples.is_empty():_last_cell_m=float(samples[0].cell_m)
func _ready_detail_coverage()->Array[Rect2]:
	if _detail_provider!=null and _detail_provider.has_method("ready_coverage_rects"):return _detail_provider.call("ready_coverage_rects")
	return []
func _sample_owned_by_detail(center:Vector2,coverage:Array[Rect2])->bool:
	for rect in coverage:
		if rect.has_point(center):return true
	return false
static func fallback_radius_for_distance(distance_m:float)->float:return maxf(4000.0,maxf(0.0,distance_m)*0.90)
func _view_bounds(focus:Vector3,distance_m:float)->Rect2:
	var points:Array[Vector3]=[];if _camera_rig.has_method("get_ground_view_corners"):var corners:Variant=_camera_rig.call("get_ground_view_corners");if typeof(corners)==TYPE_ARRAY or typeof(corners)==TYPE_PACKED_VECTOR3_ARRAY:for value in corners:if typeof(value)==TYPE_VECTOR3 and (value as Vector3).is_finite():points.append(value)
	if points.is_empty():var r:=fallback_radius_for_distance(distance_m);points=[focus+Vector3(-r,0,-r),focus+Vector3(r,0,-r),focus+Vector3(r,0,r),focus+Vector3(-r,0,r)]
	var first:Vector2=_coordinates.world_to_absolute(points[0]);var mn:=first;var mx:=first;for point in points:var a:Vector2=_coordinates.world_to_absolute(point);mn.x=minf(mn.x,a.x);mn.y=minf(mn.y,a.y);mx.x=maxf(mx.x,a.x);mx.y=maxf(mx.y,a.y);return Rect2(mn,mx-mn)
func _publish(samples:Array[Dictionary],coverage:Array[Rect2])->void:
	if _instance==null:return
	var visible_samples:Array[Dictionary]=[];_masked_samples=0
	for sample in samples:
		var cell_m:=float(sample.cell_m);var center:=Vector2((float(sample.x)+0.5)*cell_m,(float(sample.y)+0.5)*cell_m)
		if _sample_owned_by_detail(center,coverage):_masked_samples+=1
		else:visible_samples.append(sample)
	if visible_samples.is_empty():_instance.multimesh=null;return
	var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.instance_count=visible_samples.size();mm.mesh=_quad
	for i in range(visible_samples.size()):var sample:Dictionary=visible_samples[i];var cell_m:=float(sample.cell_m);var cov:=clampf(float(sample.coverage)*density_scale,0.0,1.0);var center_abs:=Vector2((float(sample.x)+0.5)*cell_m,(float(sample.y)+0.5)*cell_m);var center_world:Vector3=_coordinates.absolute_to_world(center_abs);var side:=cell_m*clampf(sqrt(cov),0.08,0.95);mm.set_instance_transform(i,Transform3D(Basis().scaled(Vector3(side,1.0,side)),center_world+Vector3(0,0.08,0)))
	_instance.multimesh=mm;_instance.visible=true
func _renderer_memory_pressure()->float:return LodPolicy.ram_pressure(int(Performance.get_monitor(Performance.MEMORY_STATIC)),ram_target_bytes,ram_hard_bytes)
func debug_snapshot()->Dictionary:return {"active":_enabled,"samples":_last_samples,"masked_by_detail":_masked_samples,"level":_last_level,"cell_m":_last_cell_m,"meters_per_pixel":_last_mpp,"build_ms":_last_build_ms,"density":density_scale,"sample_budget":base_sample_budget,"ram_pressure":_last_pressure}
