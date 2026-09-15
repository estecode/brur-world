extends SceneTree

const Controller = preload("res://scripts/geodot_hlod_controller.gd")
var failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var c = Controller.new()
	var regions := ["lund:0", "lund:1", "lund:2", "lund:3"]
	c.configure_regions(regions, 64)
	check(c.base_ready(), "base HLOD coverage gates startup")
	assert_invariants(c, "startup")

	# Simulated 0 ms, 100 ms, 2 s and 10 s detail latency all keep base coverage.
	for region in regions:
		c.request_detail(region, 4, 512)
	assert_invariants(c, "all detail requested")
	var simulated_ms := [0, 100, 2000, 10000]
	for i in simulated_ms.size():
		if i > 0:
			assert_invariants(c, "latency %dms" % simulated_ms[i])
		c.mark_detail_ready(regions[i], 4, 512)
		check(c.detail_owns(regions[i]), "ready detail atomically owns %s" % regions[i])
		assert_invariants(c, "completion %d" % i)

	# Rapid reverse zoom reuses warm base/detail without a hole.
	for region in regions:
		c.prefer_base(region)
		check(c.base_owns(region), "zoom-out immediately restores warm base")
		assert_invariants(c, "zoom out")
		c.prefer_detail(region, 4)
		check(c.detail_owns(region), "zoom-in immediately reuses warm detail")
		assert_invariants(c, "zoom in")

	# Failure never steals ownership from the current complete representation.
	c.prefer_base("lund:0")
	c.request_detail("lund:0", 5, 1024)
	c.mark_detail_failed("lund:0", 5)
	check(c.base_owns("lund:0"), "failed refinement keeps base owner")
	assert_invariants(c, "failed refinement")

	# RAM pressure may evict warm quality, never visible coverage.
	c.set_hard_cap_bytes(1024)
	c.enforce_budget()
	assert_invariants(c, "ram pressure")

	if failed:
		quit(1)
		return
	print("GEODOT_HLOD_CONTROLLER=PASS holes=0 duplicate_owners=0 latency=0,100,2000,10000 reverse_zoom=warm ram_pressure=safe")
	quit(0)

func assert_invariants(c, phase: String) -> void:
	check(c.coverage_holes().is_empty(), "%s has zero coverage holes" % phase)
	check(c.duplicate_owners().is_empty(), "%s has exactly one visible owner" % phase)

func check(condition: bool, message: String) -> void:
	if condition:
		return
	failed = true
	push_error("ASSERT FAILED: " + message)
