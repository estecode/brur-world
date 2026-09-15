extends SceneTree
const Controller = preload("res://scripts/geodot_hlod_controller.gd")
func _init() -> void:
	var c = Controller.new()
	c.configure_regions(["r"])
	c.request_detail("r", 4, 100)
	c.mark_detail_ready("r", 4, 100)
	for i in 100:
		if i % 2 == 0:
			c.prefer_base("r")
		else:
			c.prefer_detail("r", 4)
		assert(c.coverage_holes().is_empty())
		assert(c.duplicate_owners().is_empty())
	print("GEODOT_HLOD_THRESHOLD=PASS oscillations=100 holes=0 duplicate_owners=0")
	quit(0)
