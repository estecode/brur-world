extends SceneTree

const GeoDotScene = preload("res://scenes/geodot_poc.tscn")
const SETUP_TIMEOUT_S := 20.0
const SETTLE_TIMEOUT_S := 12.0
const STABLE_S := 0.50
const MEASURE_FRAMES := 360
const CELL_CROSS_INTERVAL := 90
const MAX_AVG_FRAME_MS := 33.4
const MAX_P95_FRAME_MS := 50.0
const MAX_P99_FRAME_MS := 100.0
const MAX_WORST_FRAME_MS := 250.0
var _main:Node3D;var _camera_rig:Node;var _geodot_layer:Node;var _gps_layer:Node;var _player:Node3D
var _setup_elapsed:=0.0;var _settle_elapsed:=0.0;var _stable_elapsed:=0.0;var _state:=0;var _frame_started_usec:=0;var _frame_times:Array[float]=[];var _cell_crossings:=0
var _switch_checked:=false;var _switch_requested:=false;var _gps_before:Node;var _camera_before:Node;var _player_before:Node

func _initialize()->void:
	if OS.has_environment("BRUR_PARSE_ONLY"):print("GeoDot Drive FPS real-data test parse: OK");quit(0);return
	var gpkg:=OS.get_environment("BRUR_GEODOT_GPKG");if gpkg.is_empty() or not FileAccess.file_exists(gpkg):_fail("BRUR_GEODOT_GPKG is missing");return
	if not FileAccess.file_exists("res://world_data/manifest.json"):_fail("missing world_data manifest");return
	_main=GeoDotScene.instantiate() as Node3D;get_root().add_child(_main);_camera_rig=_main.get_node_or_null("CameraRig");_geodot_layer=_main.get_node_or_null("World/GeoDotWorldLayer");_gps_layer=_main.get_node_or_null("GpsRouteLayer")
	if _camera_rig==null or _geodot_layer==null or _gps_layer==null:_fail("production composition dependencies missing")

func _process(delta:float)->bool:
	if _main==null:return false
	if _state==0:
		_setup_elapsed+=delta;_player=_gps_layer.call("get_player_vehicle") as Node3D
		if _player!=null and bool(_geodot_layer.call("is_ready")):
			if not _verify_switch():
				if _setup_elapsed>=SETUP_TIMEOUT_S:_fail("renderer switch did not reactivate within bounded base-readiness window snapshot=%s"%str(_snapshot()))
				return false
			_camera_rig.call("set_follow_target",_player);_camera_rig.call("set_drive_mode",true);_state=1
		elif _setup_elapsed>=SETUP_TIMEOUT_S:_fail("GeoDot/player did not become ready snapshot=%s"%str(_snapshot()))
	elif _state==1:
		_settle_elapsed+=delta;var s:=_snapshot();var spatial:Dictionary=s.get("spatial_hlod",{});var base_ready:=bool(spatial.get("base_ready",false));var active:=int(s.get("active_cells",0))
		if base_ready and active>0:_stable_elapsed+=delta
		else:_stable_elapsed=0.0
		if _stable_elapsed>=STABLE_S:_begin_measurement()
		elif _settle_elapsed>=SETTLE_TIMEOUT_S:_fail("base coverage/detail forward progress did not settle snapshot=%s"%str(s))
	elif _state==2:
		var now:=Time.get_ticks_usec();if _frame_started_usec>0:_frame_times.append(float(now-_frame_started_usec)/1000.0)
		if _frame_times.size()>=MEASURE_FRAMES:_finish();return false
		if _frame_times.size()>0 and _frame_times.size()%CELL_CROSS_INTERVAL==0:_cell_crossings+=1
		_frame_started_usec=Time.get_ticks_usec()
	return false

func _verify_switch()->bool:
	if _switch_checked:return true
	if not _switch_requested:
		_gps_before=_main.get_node_or_null("GpsRouteLayer");_camera_before=_main.get_node_or_null("CameraRig");_player_before=_gps_layer.call("get_player_vehicle") as Node
		if not bool(_main.call("set_geodot_renderer_enabled",false)):_fail("could not switch to legacy");return false
		if not bool(_main.call("set_geodot_renderer_enabled",true)):_fail("could not request GeoDot reactivation");return false
		_switch_requested=true;return false
	if not bool(_main.call("is_geodot_active")):return false
	if _main.get_node_or_null("GpsRouteLayer")!=_gps_before or _main.get_node_or_null("CameraRig")!=_camera_before or _gps_layer.call("get_player_vehicle")!=_player_before:_fail("renderer switch replaced gameplay state");return false
	_switch_checked=true;print("GEODOT_RENDERER_SWITCH gameplay_state_preserved=true bounded_base_readiness=true");return true

func _begin_measurement()->void:_state=2;_frame_times.clear();_frame_started_usec=Time.get_ticks_usec();print("GEODOT_DRIVE_FPS_REAL_DATA measuring snapshot=",_snapshot())
func _finish()->void:
	_frame_times.sort();var sum:=0.0;for v in _frame_times:sum+=v
	var n:=_frame_times.size();var avg:=sum/float(n);var p95:=_pct(.95);var p99:=_pct(.99);var worst:=_frame_times[n-1];var s:=_snapshot()
	print("GEODOT_DRIVE_FPS_REAL_DATA fps=%.2f avg_ms=%.3f p95_ms=%.3f p99_ms=%.3f worst_ms=%.3f frames=%d cell_crossings=%d snapshot=%s"%[1000.0/maxf(.001,avg),avg,p95,p99,worst,n,_cell_crossings,str(s)])
	if avg>MAX_AVG_FRAME_MS or p95>MAX_P95_FRAME_MS or p99>MAX_P99_FRAME_MS or worst>MAX_WORST_FRAME_MS:_fail("frame-time budget exceeded");return
	if int(s.get("active_cells",0))>int(s.get("max_resident_cells",169)):_fail("resident bound exceeded");return
	_shutdown(0)
func _pct(f:float)->float:return _frame_times[clampi(int(ceil(float(_frame_times.size())*f))-1,0,_frame_times.size()-1)]
func _snapshot()->Dictionary:return _main.call("geodot_debug_snapshot") if _main!=null and _main.has_method("geodot_debug_snapshot") else {}
func _shutdown(code:int)->void:
	if _geodot_layer!=null and _geodot_layer.has_method("shutdown"):_geodot_layer.call("shutdown")
	_geodot_layer=null;_camera_rig=null;_gps_layer=null;_player=null
	if _main!=null:_main.free();_main=null
	if code==0:print("GeoDot Drive FPS real-data test: OK")
	quit(code)
func _fail(message:String)->void:push_error("GeoDot Drive FPS real-data test failed: "+message);_shutdown(1)
