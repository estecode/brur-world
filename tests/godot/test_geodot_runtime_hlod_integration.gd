extends SceneTree

const Controller = preload("res://scripts/geodot_hlod_controller.gd")
var failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var c = Controller.new()
	c.configure_regions(["a", "b", "c", "d"])
	check(c.base_ready(), "mandatory base coverage is ready before presentation")
	for region in ["a", "b", "c", "d"]:
		c.request_detail(region, 4, 512)
	check(c.coverage_holes().is_empty(), "requests never remove visible base coverage")
	c.mark_detail_ready("b", 4, 512)
	check(c.detail_owns("b"), "ready replacement atomically owns its region")
	check(c.base_owns("a") and c.base_owns("c") and c.base_owns("d"), "unfinished neighbors retain base owners")
	check(c.duplicate_owners().is_empty(), "runtime owner has no duplicate visible owners")
	c.prefer_base("b")
	check(c.base_owns("b"), "reverse zoom immediately restores warm base")
	c.prefer_detail("b", 4)
	check(c.detail_owns("b"), "reverse zoom immediately reuses warm detail")
	if failed:
		quit(1)
		return
	print("GEODOT_RUNTIME_HLOD=PASS base_gate=true holes=0 duplicate_owners=0 reverse_zoom=warm")
	quit(0)

func check(condition: bool, message: String) -> void:
	if condition: return
	failed = true
	push_error("ASSERT FAILED: " + message)
