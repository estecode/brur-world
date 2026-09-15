extends SceneTree

const Renderer = preload("res://scripts/geodot_world_renderer.gd")
var failed := false

func _init() -> void: call_deferred("_run")

func _run() -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(19200.0, 10800.0))
	var viewport := Vector2(1920.0, 1080.0)
	var px := Renderer.projected_pixels_for_size(10.0, bounds, viewport)
	_assert(is_equal_approx(px, 1.0), "screen-space size is derived from visible metres per pixel")
	_assert(Renderer.choose_screen_lod(false, 1.0, 1.5, 2.25) == 0, "subpixel buildings enter cheap far representation")
	_assert(Renderer.choose_screen_lod(true, 1.8, 1.5, 2.25) == 0, "LOD hysteresis prevents zoom-boundary flapping")
	_assert(Renderer.choose_screen_lod(true, 2.5, 1.5, 2.25) == 1, "discernible buildings return to full geometry")
	var renderer := Renderer.new()
	renderer.max_pending_cells = 3
	renderer._queue = [{"queue_id":"a"},{"queue_id":"b"},{"queue_id":"c"},{"queue_id":"d"},{"queue_id":"e"}]
	renderer._queued = {"a":true,"b":true,"c":true,"d":true,"e":true}
	renderer._trim_queue()
	_assert(renderer._queue.size() == 3 and renderer._queued.size() == 3, "pending query queue is hard bounded")
	renderer.max_ready_cells = 2
	renderer._ready_results = [{"request":{"generation":1,"key":"a","lod":1}},{"request":{"generation":1,"key":"b","lod":1}}]
	_assert(renderer._ready_results.size() <= renderer.max_ready_cells, "completed query handoff is independently bounded")
	renderer.free()
	if failed: quit(1); return
	print("geodot runtime bounds: OK"); quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition: return
	failed = true; push_error("ASSERT FAILED: " + message)
