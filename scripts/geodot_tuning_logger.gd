extends RefCounted
class_name GeoDotTuningLogger

var _file:FileAccess=null; var _path:=""; var _last_sample_usec:=0; var _last_call_usec:=0; var _frame_ms:Array[float]=[]
func open_session(metadata:Dictionary)->String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://geodot-tuning")); var stamp:=Time.get_datetime_string_from_system().replace(":","-"); _path="user://geodot-tuning/session-%s.jsonl"%stamp; _file=FileAccess.open(_path,FileAccess.WRITE); _write({"type":"session_start","unix":Time.get_unix_time_from_system(),"metadata":metadata}); return _path
func close_session()->void:
	if _file!=null:_write({"type":"session_end","unix":Time.get_unix_time_from_system()}); _file.flush(); _file.close(); _file=null
func log_tuning_change(key:String,old_value:Variant,new_value:Variant,tuning:Dictionary)->void:_write({"type":"tuning_change","unix":Time.get_unix_time_from_system(),"key":key,"old":old_value,"new":new_value,"tuning":tuning})
func sample(snapshot:Dictionary,tuning:Dictionary,interval_s:float=1.0)->void:
	var now:=Time.get_ticks_usec()
	if _last_call_usec>0:
		_frame_ms.append(float(now-_last_call_usec)/1000.0)
		if _frame_ms.size()>600:_frame_ms.pop_front()
	_last_call_usec=now
	if now-_last_sample_usec<int(interval_s*1000000.0):return
	_last_sample_usec=now; var runtime:=snapshot.duplicate(true); runtime["frame_p95_ms"]=_percentile(_frame_ms,0.95); runtime["frame_p99_ms"]=_percentile(_frame_ms,0.99); runtime["frame_samples"]=_frame_ms.size(); _write({"type":"sample","unix":Time.get_unix_time_from_system(),"runtime":runtime,"tuning":tuning})
func path()->String:return _path
static func _percentile(values:Array[float],fraction:float)->float:
	if values.is_empty():return 0.0
	var copy:=values.duplicate(); copy.sort(); return float(copy[clampi(ceili(float(copy.size())*fraction)-1,0,copy.size()-1)])
func _write(value:Dictionary)->void:
	if _file==null:return
	_file.store_line(JSON.stringify(value)); _file.flush()
