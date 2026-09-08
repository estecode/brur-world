extends SceneTree

## Headless parse/load contract for the native Godot search adapter boundary.
## Dependencies: gps_search_client.gd and gps_search_ui.gd only; does not start the native server.

const SearchClientScript = preload("res://scripts/gps_search_client.gd")
const SearchUiScript = preload("res://scripts/gps_search_ui.gd")

func _init() -> void:
	_assert(SearchClientScript != null, "search client script loads")
	_assert(SearchUiScript != null, "search UI script loads")
	print("godot gps native-search adapter tests: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("gps native-search adapter test failed: " + message)
	quit(1)
