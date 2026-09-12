extends Node

## Exits the temporary PR-check project after automated renderer diagnostics finish.
## Dependencies: none beyond SceneTree lifecycle.

func _ready() -> void:
	get_tree().quit(0)
