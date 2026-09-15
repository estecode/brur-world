extends SceneTree
const Controller = preload("res://scripts/geodot_hlod_controller.gd")
func _init() -> void:
	var c = Controller.new()
	c.configure_regions(["r"])
	c.request_detail("r", 4, 100)
	for _second in 10:
		assert(c.base_owns("r"))
		assert(c.coverage_holes().is_empty())
	c.mark_detail_failed("r", 4)
	assert(c.base_owns("r"))
	print("GEODOT_HLOD_BLOCKED_CHILD=PASS seconds=10 holes=0")
	quit(0)
