extends RefCounted
class_name GeoDotTuningLogger

var _file: FileAccess = null
var _path := ""
var _last_sample_usec := 0

func open_session(metadata: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://geodot-tuning"))
	var stamp := Time.get_datetime_string_from_system().replace(":","-")
	_path = "user://geodot-tuning/session-%s.jsonl" % stamp
	_file = FileAccess.open(_path, FileAccess.WRITE)
	_write({"type":"session_start","unix":Time.get_unix_time_from_system(),"metadata":metadata})
	return _path

func close_session() -> void:
	if _file != null:
		_write({"type":"session_end","unix":Time.get_unix_time_from_system()}); _file.flush(); _file.close(); _file=null

func log_tuning_change(key: String, old_value: Variant, new_value: Variant, tuning: Dictionary) -> void:
	_write({"type":"tuning_change","unix":Time.get_unix_time_from_system(),"key":key,"old":old_value,"new":new_value,"tuning":tuning})

func sample(snapshot: Dictionary, tuning: Dictionary, interval_s: float = 1.0) -> void:
	var now := Time.get_ticks_usec()
	if now - _last_sample_usec < int(interval_s * 1000000.0): return
	_last_sample_usec = now
	_write({"type":"sample","unix":Time.get_unix_time_from_system(),"runtime":snapshot,"tuning":tuning})

func path() -> String: return _path

func _write(value: Dictionary) -> void:
	if _file == null: return
	_file.store_line(JSON.stringify(value)); _file.flush()
