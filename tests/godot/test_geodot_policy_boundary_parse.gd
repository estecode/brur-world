extends SceneTree

const Policy = preload("res://scripts/geodot_streaming_policy.gd")

func _init() -> void:
	var exact := Rect2(Vector2(2000.0, 2000.0), Vector2(1000.0, 1000.0))
	assert(Policy.cell_count_for_bounds(exact, 1000.0, 0) == 1)
	assert(Policy.cell_count_for_bounds(exact, 1000.0, 1) == 9)
	print("geodot policy boundary parse: OK")
	quit(0)
