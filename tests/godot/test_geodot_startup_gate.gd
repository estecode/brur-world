extends SceneTree
const Controller = preload("res://scripts/geodot_hlod_controller.gd")
func _init() -> void:
	var c = Controller.new()
	assert(not c.base_ready())
	c.configure_regions(["base:0", "base:1"])
	assert(c.base_ready())
	assert(c.coverage_holes().is_empty())
	print("GEODOT_STARTUP_GATE=PASS base_ready=true holes=0")
	quit(0)
