class_name GeoDotHlodController
extends RefCounted

const GeoDotHlodResidency = preload("res://scripts/geodot_hlod_residency.gd")

var _residency := GeoDotHlodResidency.new()
var _regions: Dictionary = {}
var _base_ready := false
var _hard_cap_bytes := 0

func configure_regions(regions: Array, base_bytes_per_region: int = 64) -> void:
	_regions.clear()
	_residency = GeoDotHlodResidency.new()
	for region_value in regions:
		var region := String(region_value)
		_regions[region] = true
		_residency.register_base(region, base_bytes_per_region)
	_base_ready = not _regions.is_empty()

func base_ready() -> bool:
	return _base_ready and _residency.coverage_holes(Array(_regions.keys())).is_empty()

func request_detail(region: String, lod: int, estimated_bytes: int) -> void:
	if not _regions.has(region):
		return
	_residency.set_desired_lod(region, lod)
	_residency.request(region, lod, estimated_bytes)

func mark_detail_ready(region: String, lod: int, bytes: int) -> void:
	_residency.mark_ready(region, lod, bytes)

func mark_detail_failed(region: String, lod: int) -> void:
	_residency.mark_failed(region, lod)

func prefer_base(region: String) -> void:
	_residency.set_desired_lod(region, 0)

func prefer_detail(region: String, lod: int) -> void:
	_residency.set_desired_lod(region, lod)

func owner_lod(region: String) -> int:
	return _residency.visible_lod(region)

func detail_owns(region: String) -> bool:
	return owner_lod(region) > 0

func base_owns(region: String) -> bool:
	return owner_lod(region) == 0

func coverage_holes() -> Array:
	return _residency.coverage_holes(Array(_regions.keys()))

func duplicate_owners() -> Array:
	return _residency.duplicate_visible_owners(Array(_regions.keys()))

func set_hard_cap_bytes(bytes: int) -> void:
	_hard_cap_bytes = max(0, bytes)
	if _hard_cap_bytes > 0:
		_residency.evict_warm_to_budget(_hard_cap_bytes)

func enforce_budget() -> void:
	if _hard_cap_bytes > 0:
		_residency.evict_warm_to_budget(_hard_cap_bytes)

func snapshot() -> Dictionary:
	var snap := _residency.snapshot()
	snap["base_ready"] = base_ready()
	snap["regions"] = _regions.size()
	snap["holes"] = coverage_holes().size()
	snap["duplicate_owners"] = duplicate_owners().size()
	return snap
