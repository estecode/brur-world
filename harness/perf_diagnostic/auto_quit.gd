extends Node

## Exits immediately after automated PR diagnostics so no manual Godot judgment is requested.
## Dependencies: SceneTree quit only.

func _ready() -> void:
	get_tree().quit(0)
