extends SceneTree

const Residency = preload("res://scripts/geodot_hlod_residency.gd")

func _init() -> void:
	var r = Residency.new()
	var required: Array[String] = ["lund:0", "lund:1", "lund:2", "lund:3"]
	for id in required: r.register_base(id, 0, 1024)
	_assert(r.coverage_holes(required) == 0, "base coverage must be complete before gameplay")

	# Simulate arbitrarily slow/out-of-order detail. Loading must never affect ownership.
	for id in required:
		r.set_desired_lod(id, 4)
		r.request(id, 4)
	_assert(r.coverage_holes(required) == 0, "10s-equivalent loading cannot create holes")
	_assert(_duplicates(r, required) == 0, "loading cannot create duplicate owners")

	r.mark_ready("lund:2", 4, 8192)
	_assert(r.visible_lod("lund:2") == 4, "ready detail must atomically replace base")
	_assert(r.visible_lod("lund:0") == 0, "unfinished neighbour must retain base")
	_assert(r.coverage_holes(required) == 0, "partial completion cannot create holes")

	# Failed child leaves the coarser owner untouched.
	r.mark_failed("lund:0", 4)
	_assert(r.visible_lod("lund:0") == 0, "failed detail must retain fallback")

	# Rapid reverse zoom must use a resident representation immediately.
	r.set_desired_lod("lund:2", 0)
	_assert(r.visible_lod("lund:2") == 0, "zoom out must reveal ready ancestor")
	r.set_desired_lod("lund:2", 4)
	_assert(r.visible_lod("lund:2") == 4, "reverse zoom must reuse warm detail")
	_assert(r.coverage_holes(required) == 0, "reverse zoom cannot create holes")
	_assert(_duplicates(r, required) == 0, "reverse zoom cannot overlap owners")

	# RAM pressure may evict warm quality, never current coverage.
	r.set_desired_lod("lund:2", 0)
	var before := r.resident_bytes()
	var evicted := r.evict_warm_to_budget(4096)
	_assert(evicted > 0 and r.resident_bytes() < before, "hard cap must evict warm detail")
	_assert(r.coverage_holes(required) == 0, "RAM pressure cannot evict visible coverage")

	var snap: Dictionary = r.snapshot()
	_assert(int(snap.coverage_holes) == 0, "final coverage")
	_assert(int(snap.duplicate_visible_owners) == 0, "final ownership")
	print("GEODOT_HLOD_RESIDENCY=PASS holes=0 duplicate_owners=0 reverse_zoom=warm ram_pressure=safe")
	quit(0)

func _duplicates(r, required: Array[String]) -> int:
	var total := 0
	for id in required: total += r.duplicate_visible_owners(id)
	return total

func _assert(value: bool, message: String) -> void:
	if value: return
	push_error(message)
	print("GEODOT_HLOD_RESIDENCY=FAIL ", message)
	quit(1)
