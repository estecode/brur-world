extends Node

## Mounts the self-contained Windows runtime world-data pack before the main scene starts.
##
## Dependencies:
## - Windows exports place brur-world-data.zip beside the executable.
## - Local/editor runs keep using the normal res://world_data tree and do not mount a pack.

const PACK_FILENAME := "brur-world-data.zip"
const REQUIRED_MANIFEST := "res://world_data/manifest.json"

func _enter_tree() -> void:
	if not OS.has_feature("windows"):
		return
	if FileAccess.file_exists(REQUIRED_MANIFEST):
		return

	var pack_path := OS.get_executable_path().get_base_dir().path_join(PACK_FILENAME)
	if not FileAccess.file_exists(pack_path):
		_fail("missing runtime world pack beside executable: %s" % pack_path)
		return
	if not ProjectSettings.load_resource_pack(pack_path, true):
		_fail("failed to mount runtime world pack: %s" % pack_path)
		return
	if not FileAccess.file_exists(REQUIRED_MANIFEST):
		_fail("runtime world pack mounted without %s" % REQUIRED_MANIFEST)
		return

	print("WINDOWS_RUNTIME_PACK=LOADED %s" % pack_path)

func _fail(message: String) -> void:
	push_error("WINDOWS_RUNTIME_PACK=FAIL %s" % message)
	get_tree().quit(78)
