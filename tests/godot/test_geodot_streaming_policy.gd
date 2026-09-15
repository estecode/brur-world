extends SceneTree

const Policy = preload("res://scripts/geodot_streaming_policy.gd")
var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var exact := Rect2(Vector2(2000.0, 2000.0), Vector2(1000.0, 1000.0))
	_assert(Policy.cell_count_for_bounds(exact, 1000.0, 0) == 1, "exact maximum boundary is half-open")
	_assert(Policy.cell_count_for_bounds(exact, 1000.0, 1) == 9, "one-cell margin adds exactly one ring")
	var zero := Rect2(Vector2(2000.0, 2000.0), Vector2.ZERO)
	_assert(Policy.cell_count_for_bounds(zero, 1000.0, 0) == 1, "zero-area focus still owns one containing cell")
	var small := Rect2(Vector2.ZERO, Vector2(8000.0, 6000.0))
	_assert(Policy.bounded_cell_size_for_bounds(small, 2000.0, 1, 169) == 2000.0, "normal viewport keeps base query-cell detail")
	var huge := Rect2(Vector2.ZERO, Vector2(100000.0, 80000.0))
	var adaptive := Policy.bounded_cell_size_for_bounds(huge, 2000.0, 1, 169)
	_assert(adaptive > 2000.0, "large viewport increases query-cell scale instead of truncating visible coverage")
	_assert(Policy.cell_count_for_bounds(huge, adaptive, 1) <= 169, "adaptive viewport remains inside resident-cell bound")
	_assert(Policy.bounded_cell_size_for_bounds(huge, 2000.0, 1, 169) == adaptive, "adaptive cell scale is deterministic")
	if _failed:
		quit(1)
		return
	print("geodot streaming policy: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition: return
	_failed = true
	push_error("ASSERT FAILED: " + message)
