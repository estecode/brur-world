extends RefCounted
class_name GeoDotHlodResidency

# Pure residency/ownership policy. Rendering and GeoDot I/O are adapters.
# A region always keeps its current READY owner until a better READY
# representation can replace it atomically.

const ABSENT := 0
const LOADING := 1
const READY := 2
const VISIBLE := 3
const WARM := 4

var _regions: Dictionary = {}
var _tick := 0

func register_base(region_id: String, lod: int = 0, memory_bytes: int = 0) -> void:
	var region := _region(region_id)
	var reps: Dictionary = region.representations
	reps[lod] = {"state": VISIBLE, "memory_bytes": maxi(0, memory_bytes), "last_used": _next_tick()}
	region["visible_lod"] = lod
	region["desired_lod"] = maxi(lod, int(region.desired_lod))
	_regions[region_id] = region

func request(region_id: String, lod: int) -> void:
	var region := _region(region_id)
	region["desired_lod"] = maxi(lod, int(region.desired_lod))
	var reps: Dictionary = region.representations
	if not reps.has(lod): reps[lod] = {"state": LOADING, "memory_bytes": 0, "last_used": _next_tick()}
	elif int(reps[lod].state) == ABSENT: reps[lod]["state"] = LOADING
	_regions[region_id] = region

func mark_ready(region_id: String, lod: int, memory_bytes: int = 0) -> void:
	var region := _region(region_id)
	var reps: Dictionary = region.representations
	var rep: Dictionary = reps.get(lod, {})
	rep["state"] = READY
	rep["memory_bytes"] = maxi(0, memory_bytes)
	rep["last_used"] = _next_tick()
	reps[lod] = rep
	_regions[region_id] = region
	_commit_best_ready(region_id)

func mark_failed(region_id: String, lod: int) -> void:
	var region := _region(region_id)
	var reps: Dictionary = region.representations
	if reps.has(lod) and int(reps[lod].state) == LOADING:
		reps.erase(lod)
	_regions[region_id] = region

func set_desired_lod(region_id: String, lod: int) -> void:
	var region := _region(region_id)
	region["desired_lod"] = maxi(0, lod)
	_regions[region_id] = region
	_commit_best_ready(region_id)

func visible_lod(region_id: String) -> int:
	return int(_region(region_id).visible_lod)

func has_coverage(region_id: String) -> bool:
	var region := _region(region_id)
	var visible := int(region.visible_lod)
	return visible >= 0 and region.representations.has(visible) and int(region.representations[visible].state) == VISIBLE

func coverage_holes(required_regions: Array[String]) -> int:
	var holes := 0
	for region_id in required_regions:
		if not has_coverage(region_id): holes += 1
	return holes

func duplicate_visible_owners(region_id: String) -> int:
	var count := 0
	for rep_value in _region(region_id).representations.values():
		if int((rep_value as Dictionary).get("state", ABSENT)) == VISIBLE: count += 1
	return maxi(0, count - 1)

func resident_bytes() -> int:
	var total := 0
	for region_value in _regions.values():
		for rep_value in (region_value as Dictionary).representations.values():
			var rep: Dictionary = rep_value
			if int(rep.get("state", ABSENT)) >= READY: total += int(rep.get("memory_bytes", 0))
	return total

func evict_warm_to_budget(hard_bytes: int) -> int:
	var evicted := 0
	while resident_bytes() > maxi(0, hard_bytes):
		var candidate_region := ""
		var candidate_lod := -1
		var oldest := 9223372036854775807
		for region_key in _regions.keys():
			var region: Dictionary = _regions[region_key]
			for lod_key in region.representations.keys():
				var rep: Dictionary = region.representations[lod_key]
				if int(rep.state) != WARM: continue
				var used := int(rep.get("last_used", 0))
				if candidate_lod < 0 or used < oldest:
					candidate_region = String(region_key); candidate_lod = int(lod_key); oldest = used
		if candidate_lod < 0: break
		var region: Dictionary = _regions[candidate_region]
		region.representations.erase(candidate_lod)
		_regions[candidate_region] = region
		evicted += 1
	return evicted

func snapshot() -> Dictionary:
	var holes := 0
	var duplicates := 0
	for region_id in _regions.keys():
		if not has_coverage(String(region_id)): holes += 1
		duplicates += duplicate_visible_owners(String(region_id))
	return {"regions": _regions.size(), "coverage_holes": holes, "duplicate_visible_owners": duplicates, "resident_bytes": resident_bytes()}

func _commit_best_ready(region_id: String) -> void:
	var region := _region(region_id)
	var reps: Dictionary = region.representations
	var desired := int(region.desired_lod)
	var current := int(region.visible_lod)
	var best := current
	for lod_key in reps.keys():
		var lod := int(lod_key)
		var state := int(reps[lod_key].state)
		if lod <= desired and state >= READY and state != WARM and lod > best: best = lod
	# Downgrade only to a READY representation when desired quality decreases.
	if current > desired:
		best = -1
		for lod_key in reps.keys():
			var lod := int(lod_key); var state := int(reps[lod_key].state)
			if lod <= desired and state >= READY and (best < 0 or lod > best): best = lod
	if best < 0 or best == current: return
	if current >= 0 and reps.has(current):
		var old: Dictionary = reps[current]; old["state"] = WARM; old["last_used"] = _next_tick(); reps[current] = old
	var next: Dictionary = reps[best]; next["state"] = VISIBLE; next["last_used"] = _next_tick(); reps[best] = next
	region["visible_lod"] = best
	_regions[region_id] = region

func _region(region_id: String) -> Dictionary:
	if _regions.has(region_id): return (_regions[region_id] as Dictionary).duplicate(true)
	return {"desired_lod": 0, "visible_lod": -1, "representations": {}}

func _next_tick() -> int:
	_tick += 1
	return _tick
