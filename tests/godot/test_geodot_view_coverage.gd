extends SceneTree

const Renderer = preload("res://scripts/geodot_world_renderer.gd")

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_assert(Renderer.coverage_radius_for_altitude(0.0, 3000.0, 3, 6, 0.72) == 3, "ground view keeps baseline 7x7 coverage")
	_assert(Renderer.coverage_radius_for_altitude(9000.0, 3000.0, 3, 6, 0.72) == 4, "9 km view expands beyond the old fixed footprint")
	_assert(Renderer.coverage_radius_for_altitude(24000.0, 3000.0, 3, 6, 0.72) == 6, "24 km view reaches bounded 13x13 coverage")
	_assert(Renderer.coverage_radius_for_altitude(100000.0, 3000.0, 3, 6, 0.72) == 6, "coverage remains explicitly bounded at extreme altitude")
	if _failed:
		quit(1)
		return
	print("geodot view coverage: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("ASSERT FAILED: " + message)
