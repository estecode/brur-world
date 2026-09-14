extends Node

## Mounts the self-contained Windows runtime world-data pack and records early packaged-runtime health.
##
## Dependencies:
## - Windows exports place brur-world-data.zip beside the executable.
## - The client bundle provides a writable logs/ directory beside the executable.
## - Local/editor runs keep using the normal res://world_data tree and do not mount a pack.

const PACK_FILENAME := "brur-world-data.zip"
const REQUIRED_MANIFEST := "res://world_data/manifest.json"
const LOG_DIRECTORY := "logs"
const LOG_FILENAME := "windows-runtime.log"
const HEARTBEAT_INTERVAL_SECONDS := 1.0
const HEARTBEAT_SAMPLE_LIMIT := 15

var _runtime_log: FileAccess = null
var _heartbeat_elapsed := 0.0
var _heartbeat_samples := 0

func _enter_tree() -> void:
	if not OS.has_feature("windows"):
		return
	_open_runtime_log()
	_log_runtime("startup executable=%s" % OS.get_executable_path())
	if FileAccess.file_exists(REQUIRED_MANIFEST):
		_log_runtime("world_data=embedded_or_local")
		return

	var pack_path := OS.get_executable_path().get_base_dir().path_join(PACK_FILENAME)
	if not FileAccess.file_exists(pack_path):
		_fail("missing runtime world pack beside executable: %s" % pack_path)
		return
	var mount_started := Time.get_ticks_msec()
	if not ProjectSettings.load_resource_pack(pack_path, true):
		_fail("failed to mount runtime world pack: %s" % pack_path)
		return
	var mount_ms := Time.get_ticks_msec() - mount_started
	if not FileAccess.file_exists(REQUIRED_MANIFEST):
		_fail("runtime world pack mounted without %s" % REQUIRED_MANIFEST)
		return

	_log_runtime("pack=loaded mount_ms=%d path=%s" % [mount_ms, pack_path])
	print("WINDOWS_RUNTIME_PACK=LOADED %s mount_ms=%d" % [pack_path, mount_ms])

func _process(delta: float) -> void:
	if _runtime_log == null or _heartbeat_samples >= HEARTBEAT_SAMPLE_LIMIT:
		return
	_heartbeat_elapsed += delta
	if _heartbeat_elapsed < HEARTBEAT_INTERVAL_SECONDS:
		return
	_heartbeat_elapsed = 0.0
	_heartbeat_samples += 1
	_log_runtime(
		"heartbeat sample=%d fps=%.1f process_frames=%d" % [
			_heartbeat_samples,
			Engine.get_frames_per_second(),
			Engine.get_process_frames(),
		]
	)

func _open_runtime_log() -> void:
	var executable_dir := OS.get_executable_path().get_base_dir()
	var log_dir := executable_dir.path_join(LOG_DIRECTORY)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(log_dir)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		push_warning("WINDOWS_RUNTIME_LOG=FAIL mkdir %s: %s" % [log_dir, error_string(mkdir_error)])
		return
	var log_path := log_dir.path_join(LOG_FILENAME)
	_runtime_log = FileAccess.open(log_path, FileAccess.WRITE)
	if _runtime_log == null:
		push_warning("WINDOWS_RUNTIME_LOG=FAIL open %s" % log_path)
		return
	_runtime_log.store_line("WINDOWS_RUNTIME_LOG=START %s" % Time.get_datetime_string_from_system())
	_runtime_log.flush()
	print("WINDOWS_RUNTIME_LOG=%s" % log_path)

func _log_runtime(message: String) -> void:
	if _runtime_log == null:
		return
	_runtime_log.store_line("%s ticks_ms=%d %s" % [Time.get_datetime_string_from_system(), Time.get_ticks_msec(), message])
	_runtime_log.flush()

func _fail(message: String) -> void:
	_log_runtime("FAIL %s" % message)
	push_error("WINDOWS_RUNTIME_PACK=FAIL %s" % message)
	get_tree().quit(78)
