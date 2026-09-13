extends SceneTree

## Verifies the driving harness script compiles under the project Godot version.
##
## Dependencies:
## - Loads only the existing production-backed driving harness script.
## - Does not instantiate the harness or require runtime world data.

func _initialize() -> void:
	var script := load("res://harness/driving/driving_harness.gd")
	if script == null:
		push_error("driving harness parse regression: script failed to load")
		quit(1)
		return
	print("DRIVING_HARNESS_PARSE=PASS")
	quit(0)
