extends Node

## Writes shared showcase diagnostics to revision-identifiable runtime logs beside packaged clients.
##
## Dependencies:
## - Reads Engine/OS/DisplayServer/RenderingServer runtime information and packaged build manifests.
## - Reads camera/building state through explicit references supplied by the showcase composition.
## - Does not modify world, routing, streaming, or source data.

var _camera_rig: Node = null
var _buildings: Node = null
var _file: FileAccess = null
var _sample_accum := 0.0
var _elapsed := 0.0
var _fps_total := 0.0
var _fps_min := INF
var _fps_max := 0.0
var _fps_samples := 0
var _closed := false
var _last_snapshot := {}

func setup(camera_rig: Node, buildings: Node) -> void:
	_camera_rig = camera_rig
	_buildings = buildings
	_open_log()

func _process(delta: float) -> void:
	if _file == null:
		return
	_elapsed += delta
	_sample_accum += delta
	if _sample_accum < 1.0:
		return
	_sample_accum = 0.0
	_write_sample()

func _exit_tree() -> void:
	_close_log()

func _open_log() -> void:
	var root := OS.get_executable_path().get_base_dir()
	var exe_name := OS.get_executable_path().get_file().get_basename()
	var logs_dir := root.path_join("logs")
	var error := DirAccess.make_dir_recursive_absolute(logs_dir)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("Unable to create runtime logs directory: %s" % logs_dir)
		return
	var now := Time.get_datetime_dict_from_system()
	var stamp := "%04d%02d%02d-%02d%02d%02d" % [
		int(now.get("year", 0)), int(now.get("month", 0)), int(now.get("day", 0)),
		int(now.get("hour", 0)), int(now.get("minute", 0)), int(now.get("second", 0)),
	]
	var path := logs_dir.path_join("%s-%s.log" % [exe_name, stamp])
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_error("Unable to create benchmark log: %s" % path)
		return

	_write_line("BRUR runtime diagnostics")
	_write_line("log_path=%s" % path)
	_write_line("runtime_mode=world_showcase_windows")
	_write_manifest_identity(root)
	_write_line("os_name=%s" % OS.get_name())
	_write_line("os_version=%s" % OS.get_version())
	_write_line("processor=%s" % OS.get_processor_name())
	_write_line("processor_threads=%d" % OS.get_processor_count())
	_write_line("gpu=%s" % RenderingServer.get_video_adapter_name())
	_write_line("gpu_vendor=%s" % RenderingServer.get_video_adapter_vendor())
	_write_line("rendering_driver=%s" % RenderingServer.get_current_rendering_driver_name())
	if RenderingServer.has_method("get_video_adapter_api_version"):
		_write_line("graphics_api=%s" % str(RenderingServer.call("get_video_adapter_api_version")))
	if OS.has_method("get_memory_info"):
		var memory_info: Variant = OS.call("get_memory_info")
		if typeof(memory_info) == TYPE_DICTIONARY:
			_write_line("memory_physical_bytes=%d" % int(memory_info.get("physical", 0)))
	var screen_size := DisplayServer.screen_get_size()
	_write_line("screen=%dx%d" % [screen_size.x, screen_size.y])
	_write_line("window=%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y])
	_write_line("event=startup_complete")
	_write_line("--- samples: elapsed_s,fps,frame_ms,altitude_m,active_tiles,pending_tiles,wanted_tiles,records ---")

func _write_manifest_identity(root: String) -> void:
	var build_info := _read_json(root.path_join("build_info.json"))
	var bundle_info := _read_json(root.path_join("client_bundle_info.json"))
	if build_info.is_empty():
		_write_line("build_identity=missing build_info.json")
	else:
		_write_line("repository=%s" % String(build_info.get("repository", "unknown")))
		_write_line("ref=%s" % String(build_info.get("ref", "unknown")))
		_write_line("pr=%s" % str(build_info.get("pr", null)))
		_write_line("issue=%s" % str(build_info.get("issue", null)))
		_write_line("commit=%s" % String(build_info.get("commit", "unknown")))
		_write_line("godot_version=%s" % String(build_info.get("godot_version", "unknown")))
		_write_line("export_target=%s" % String(build_info.get("export_target", "unknown")))
	if bundle_info.is_empty():
		_write_line("world_data_identity=missing client_bundle_info.json")
	else:
		_write_line("world_data_source_manifest_sha256=%s" % String(bundle_info.get("world_data_source_manifest_sha256", "unknown")))
		var runtime_files: Dictionary = bundle_info.get("runtime_files", {})
		_write_line("runtime_file_count=%d" % runtime_files.size())
		for key in runtime_files.keys():
			_write_line("runtime_file_sha256[%s]=%s" % [String(key), String(runtime_files[key])])

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_write_line("load_failure=%s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_write_line("load_failure=invalid_json:%s" % path)
		return {}
	return parsed

func _write_sample() -> void:
	var fps := float(Engine.get_frames_per_second())
	if fps > 0.0:
		_fps_total += fps
		_fps_min = minf(_fps_min, fps)
		_fps_max = maxf(_fps_max, fps)
		_fps_samples += 1
	var altitude := float(_camera_rig.call("get_altitude")) if _camera_rig != null else -1.0
	var snapshot: Dictionary = _buildings.call("debug_snapshot") if _buildings != null else {}
	var frame_ms := 1000.0 / fps if fps > 0.0 else 0.0
	_write_state_transition(snapshot)
	_write_line("%.1f,%.1f,%.3f,%.1f,%d,%d,%d,%d" % [
		_elapsed, fps, frame_ms, altitude,
		int(snapshot.get("active_tiles", 0)), int(snapshot.get("pending_tiles", 0)),
		int(snapshot.get("wanted_tiles", 0)), int(snapshot.get("active_records", 0)),
	])

func _write_state_transition(snapshot: Dictionary) -> void:
	if snapshot == _last_snapshot:
		return
	var keys := ["active_tiles", "pending_tiles", "wanted_tiles", "active_records"]
	var changed := false
	for key in keys:
		if int(snapshot.get(key, 0)) != int(_last_snapshot.get(key, 0)):
			changed = true
			break
	if changed:
		_write_line("event=streaming_state active=%d pending=%d wanted=%d records=%d" % [
			int(snapshot.get("active_tiles", 0)), int(snapshot.get("pending_tiles", 0)),
			int(snapshot.get("wanted_tiles", 0)), int(snapshot.get("active_records", 0)),
		])
	_last_snapshot = snapshot.duplicate(true)

func _close_log() -> void:
	if _closed or _file == null:
		return
	_closed = true
	if _fps_samples > 0:
		_write_line("--- summary ---")
		_write_line("fps_avg=%.1f" % (_fps_total / float(_fps_samples)))
		_write_line("fps_min=%.1f" % _fps_min)
		_write_line("fps_max=%.1f" % _fps_max)
		_write_line("samples=%d" % _fps_samples)
	_write_line("event=shutdown")
	_file.flush()
	_file = null

func _write_line(text: String) -> void:
	if _file == null:
		return
	_file.store_line(text)
	_file.flush()
