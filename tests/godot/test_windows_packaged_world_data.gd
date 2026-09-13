extends SceneTree

## Verifies the exported PCK contains the production world-data contract at res://world_data.
##
## Dependencies:
## - Reads only packaged runtime files through Godot's virtual filesystem.
## - Does not depend on rendering, native GPS processes, or local checkout data.

const DELIVERY_MANIFEST := "windows_runtime_manifest.json"

const REQUIRED_FILES := [
	"manifest.json",
	"background.brmap",
	"city_light_density.jsonl",
	"routing.brg",
	"routing_snap.brs",
	"routing_geometry.brh",
	"search_index.bsi",
	"traffic_signals.json",
]

const REQUIRED_DIRS := [
	"lod0",
	"lod1",
	"lod2",
	"poi_tiles",
	"building_tiles",
]

func _initialize() -> void:
	for name in REQUIRED_FILES:
		var path := "res://world_data/%s" % name
		if not FileAccess.file_exists(path):
			_fail("missing %s" % path)
			return

	for name in REQUIRED_DIRS:
		var path := "res://world_data/%s" % name
		if not _dir_has_file(path):
			_fail("missing or empty %s" % path)
			return

	if DirAccess.open("res://world_data/osm_source_cache") != null:
		_fail("source cache was packaged")
		return

	var delivery_path := "res://world_data/%s" % DELIVERY_MANIFEST
	var delivery_file := FileAccess.open(delivery_path, FileAccess.READ)
	if delivery_file == null:
		_fail("missing %s" % delivery_path)
		return
	var parsed: Variant = JSON.parse_string(delivery_file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("invalid %s" % delivery_path)
		return
	var files_value: Variant = (parsed as Dictionary).get("files", [])
	if typeof(files_value) != TYPE_ARRAY:
		_fail("invalid file list in %s" % delivery_path)
		return
	var files: Array = files_value as Array
	if files.is_empty():
		_fail("empty file list in %s" % delivery_path)
		return
	for relative_value in files:
		var relative := String(relative_value)
		if relative.is_empty() or not FileAccess.file_exists("res://world_data/" + relative):
			_fail("selected runtime file missing from PCK: %s" % relative)
			return

	print("WINDOWS_PACK_DATA=OK files=%d" % files.size())
	quit(0)

func _fail(message: String) -> void:
	push_error("WINDOWS_PACK_DATA=FAIL %s" % message)
	quit(1)

func _dir_has_file(path: String) -> bool:
	var directory := DirAccess.open(path)
	if directory == null:
		return false
	directory.list_dir_begin()
	while true:
		var entry := directory.get_next()
		if entry.is_empty():
			break
		if entry == "." or entry == "..":
			continue
		if directory.current_is_dir():
			if _dir_has_file(path.path_join(entry)):
				directory.list_dir_end()
				return true
		else:
			directory.list_dir_end()
			return true
	directory.list_dir_end()
	return false
