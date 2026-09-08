extends SceneTree

## Headless input -> expected-output tests for the isolated Godot GPS search index.
## Dependencies: scripts/gps_search_index.gd only; no routing, rendering or native server.

const SearchIndexScript = preload("res://scripts/gps_search_index.gd")

func _init() -> void:
	_assert(SearchIndexScript.normalize_search_text("SÖDERSJUKHUSET") == "sodersjukhuset", "normalization removes Swedish diacritics")
	_assert(SearchIndexScript.normalize_search_text("  City--Garaget  ") == "city garaget", "normalization tokenizes punctuation")

	var temp_path: String = "user://gps_search_test_bsi1.jsonl"
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	_assert(file != null, "test index can be created")
	file.store_line('{"format":"BSI1","count":4}')
	file.store_line('{"id":"address:node:1","kind":"address","display":"Storgatan 10","subtitle":"Malmö","x":10.0,"y":20.0,"search":"storgatan 10 malmo"}')
	file.store_line('{"id":"poi:node:2","kind":"poi","display":"City Garaget","subtitle":"garage","x":30.0,"y":40.0,"search":"city garaget garage"}')
	file.store_line('{"id":"poi:node:3","kind":"poi","display":"City Garaget","subtitle":"Lund","x":50.0,"y":60.0,"search":"city garaget lund"}')
	file.store_line('{"id":"poi:node:4","kind":"poi","display":"Södersjukhuset","subtitle":"hospital","x":70.0,"y":80.0,"search":"sodersjukhuset hospital"}')
	file.close()

	var index = SearchIndexScript.new()
	var loaded: Dictionary = index.load_file(temp_path)
	_assert(bool(loaded.get("success", false)), "BSI1 index loads")
	_assert(int(loaded.get("count", 0)) == 4, "BSI1 count is exact")

	var address: Array[Dictionary] = index.search("storgatan 10")
	_assert(address.size() == 1, "known address is found")
	_assert(str(address[0]["id"]) == "address:node:1", "known address id is exact")
	_assert(float(address[0]["x"]) == 10.0 and float(address[0]["y"]) == 20.0, "known address coordinates are exact")

	var first: Array[Dictionary] = index.search("city gar")
	var second: Array[Dictionary] = index.search("CITY GAR")
	_assert(first.size() == 2 and second.size() == 2, "partial-token search finds both duplicate names")
	_assert(str(first[0]["id"]) == "poi:node:2" and str(first[1]["id"]) == "poi:node:3", "duplicate names use deterministic id tie-break")
	_assert(str(first[0]["id"]) == str(second[0]["id"]) and str(first[1]["id"]) == str(second[1]["id"]), "same semantic query gives same ordering")

	var hospital: Array[Dictionary] = index.search("södersjukhuset")
	_assert(hospital.size() == 1 and str(hospital[0]["id"]) == "poi:node:4", "diacritic-insensitive POI search matches Python contract")
	_assert(index.search("city", 1).size() == 1, "result limit is enforced")
	_assert(index.search("", 8).is_empty(), "empty query returns no results")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))
	print("godot gps search-index tests: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("gps search-index test failed: " + message)
	quit(1)
