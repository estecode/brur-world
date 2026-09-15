extends Node3D
class_name GeoDotFarRenderer

const FarCache = preload("res://scripts/geodot_far_cache.gd")
const LodPolicy = preload("res://scripts/geodot_lod_policy.gd")

@export var enter_distance_m := 55000.0
@export var exit_distance_m := 50000.0
@export var target_screen_cell_px := 5.0
@export var base_sample_budget := 12000
@export var hard_sample_cap := 24000
@export var density_scale := 1.0
@export var batch_grid_cells := 8
@export var max_batches := 96

var ram_target_bytes := 2048 * 1024 * 1024
var ram_hard_bytes := 2560 * 1024 * 1024
var _coordinates = null
var _camera_rig: Node = null
var _detail_provider: Node = null
var _cache = FarCache.new()
var _quad: QuadMesh = null
var _material: StandardMaterial3D = null
var _batches: Dictionary = {}
var _enabled := false
var _cache_ready := false
var _coverage_ready := false
var _refresh_accum := 0.25
var _last_samples := 0
var _last_level := -1
var _last_cell_m := 0.0
var _last_mpp := 0.0
var _last_build_ms := 0.0
var _last_pressure := 0.0
var _last_signature := ""
var _masked_samples := 0

func setup(world_coordinates, camera_rig: Node, cache_path: String) -> Dictionary:
	_coordinates = world_coordinates
	_camera_rig = camera_rig
	var opened := _cache.open(cache_path)
	if opened.get("ok", false) != true:
		return opened
	_cache_ready = true
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = Color(0.32, 0.33, 0.34, 0.72)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_quad = QuadMesh.new()
	_quad.orientation = PlaneMesh.FACE_Y
	_quad.size = Vector2.ONE
	_quad.material = _material
	_enabled = true
	set_process(true)
	return opened

func set_detail_provider(provider: Node) -> void:
	_detail_provider = provider
	_last_signature = ""

func is_cache_ready() -> bool:
	return _cache_ready

func is_coverage_ready() -> bool:
	return _cache_ready and _coverage_ready

func shutdown() -> void:
	set_process(false)
	_enabled = false
	_cache_ready = false
	_coverage_ready = false
	_cache.close()
	_clear_batches()
	_quad = null
	_material = null
	_coordinates = null
	_camera_rig = null
	_detail_provider = null

func _exit_tree() -> void:
	shutdown()

# Compatibility only. Ownership is spatial; there is no global far/detail switch.
func set_detail_owner(_value: bool) -> void:
	pass

func set_transition_hold(_value: bool) -> void:
	pass

func set_tuning(values: Dictionary) -> void:
	if values.has("far_density"):
		density_scale = clampf(float(values.far_density), 0.05, 4.0)
	if values.has("far_pixel_budget"):
		base_sample_budget = clampi(int(values.far_pixel_budget), 500, hard_sample_cap)
	if values.has("far_tile_pixels"):
		target_screen_cell_px = clampf(float(values.far_tile_pixels), 1.0, 32.0)
	if values.has("ram_target_mb"):
		ram_target_bytes = maxi(256, int(values.ram_target_mb)) * 1024 * 1024
	if values.has("ram_hard_mb"):
		ram_hard_bytes = maxi(int(values.get("ram_target_mb", 2048)), int(values.ram_hard_mb)) * 1024 * 1024
	_last_signature = ""

func _process(delta: float) -> void:
	if not _enabled or _camera_rig == null:
		return
	_refresh_accum += delta
	if _refresh_accum < 0.10:
		return
	_refresh_accum = 0.0
	_refresh()

func _refresh() -> void:
	if not _camera_rig.has_method("get_focus_world"):
		return
	var focus: Vector3 = _camera_rig.call("get_focus_world")
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera == null:
		return
	var distance := camera.global_position.distance_to(focus)
	var bounds := _view_bounds(focus, distance)
	var viewport := get_viewport().get_visible_rect().size
	_last_mpp = LodPolicy.meters_per_pixel(bounds, viewport)
	var level := _cache.choose_level(maxf(2000.0, _last_mpp * target_screen_cell_px))
	if level < 0:
		return
	_last_pressure = _renderer_memory_pressure()
	var budget := LodPolicy.sample_budget(base_sample_budget, density_scale * LodPolicy.quality_scale_for_pressure(_last_pressure), hard_sample_cap)
	var cell_m := _cache.level_cell_size(level)
	var qmin := Vector2(floor(bounds.position.x / cell_m), floor(bounds.position.y / cell_m))
	var qmax := Vector2(ceil(bounds.end.x / cell_m), ceil(bounds.end.y / cell_m))
	var coverage := _ready_detail_coverage()
	var signature := "%d:%d:%d:%d:%d:%d:%d" % [level, int(qmin.x), int(qmin.y), int(qmax.x), int(qmax.y), budget, coverage.hash()]
	if signature == _last_signature:
		return
	var started := Time.get_ticks_usec()
	var samples := _cache.query_bounds(bounds, level, budget, density_scale)
	_publish(samples, coverage)
	_last_signature = signature
	_last_level = level
	_last_samples = samples.size()
	_last_build_ms = float(Time.get_ticks_usec() - started) / 1000.0
	if not samples.is_empty():
		_last_cell_m = float(samples[0].cell_m)
	# Empty rural views are valid coverage too: the cache query completed and
	# authoritatively found no aggregate building samples for the requested view.
	_coverage_ready = true

func _ready_detail_coverage() -> Array[Rect2]:
	if _detail_provider != null and _detail_provider.has_method("ready_coverage_rects"):
		return _detail_provider.call("ready_coverage_rects")
	return []

static func sample_fully_owned_by_detail(sample_rect: Rect2, coverage: Array[Rect2]) -> bool:
	for rect in coverage:
		if rect.encloses(sample_rect):
			return true
	return false

static func fallback_radius_for_distance(distance_m: float) -> float:
	return maxf(4000.0, maxf(0.0, distance_m) * 0.90)

func _view_bounds(focus: Vector3, distance_m: float) -> Rect2:
	var points: Array[Vector3] = []
	if _camera_rig.has_method("get_ground_view_corners"):
		var corners: Variant = _camera_rig.call("get_ground_view_corners")
		if typeof(corners) == TYPE_ARRAY or typeof(corners) == TYPE_PACKED_VECTOR3_ARRAY:
			for value in corners:
				if typeof(value) == TYPE_VECTOR3 and (value as Vector3).is_finite():
					points.append(value)
	if points.is_empty():
		var radius := fallback_radius_for_distance(distance_m)
		points = [focus + Vector3(-radius, 0, -radius), focus + Vector3(radius, 0, -radius), focus + Vector3(radius, 0, radius), focus + Vector3(-radius, 0, radius)]
	var first: Vector2 = _coordinates.world_to_absolute(points[0])
	var minimum := first
	var maximum := first
	for point in points:
		var absolute: Vector2 = _coordinates.world_to_absolute(point)
		minimum.x = minf(minimum.x, absolute.x)
		minimum.y = minf(minimum.y, absolute.y)
		maximum.x = maxf(maximum.x, absolute.x)
		maximum.y = maxf(maximum.y, absolute.y)
	return Rect2(minimum, maximum - minimum)

func _publish(samples: Array[Dictionary], coverage: Array[Rect2]) -> void:
	var grouped: Dictionary = {}
	_masked_samples = 0
	for sample in samples:
		var cell_m := float(sample.cell_m)
		var sample_rect := Rect2(Vector2(float(sample.x) * cell_m, float(sample.y) * cell_m), Vector2(cell_m, cell_m))
		if sample_fully_owned_by_detail(sample_rect, coverage):
			_masked_samples += 1
			continue
		var batch_x := floori(float(sample.x) / float(maxi(1, batch_grid_cells)))
		var batch_y := floori(float(sample.y) / float(maxi(1, batch_grid_cells)))
		var key := "%d:%d" % [batch_x, batch_y]
		if not grouped.has(key):
			grouped[key] = []
		(grouped[key] as Array).append(sample)
	var keys := grouped.keys()
	keys.sort()
	if keys.size() > maxi(1, max_batches):
		keys.resize(maxi(1, max_batches))
	var keep: Dictionary = {}
	for key_value in keys:
		var key := String(key_value)
		keep[key] = true
		_publish_batch(key, grouped[key])
	for existing_value in _batches.keys():
		var existing := String(existing_value)
		if not keep.has(existing):
			_remove_batch(existing)

func _publish_batch(key: String, samples: Array) -> void:
	var instance: MultiMeshInstance3D = _batches.get(key) as MultiMeshInstance3D
	if instance == null:
		instance = MultiMeshInstance3D.new()
		instance.name = "GeoDotFarBatch_%s" % key.replace(":", "_")
		add_child(instance)
		_batches[key] = instance
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = samples.size()
	mm.mesh = _quad
	for i in range(samples.size()):
		var sample: Dictionary = samples[i]
		var cell_m := float(sample.cell_m)
		var coverage := clampf(float(sample.coverage) * density_scale, 0.0, 1.0)
		var center_abs := Vector2((float(sample.x) + 0.5) * cell_m, (float(sample.y) + 0.5) * cell_m)
		var center_world: Vector3 = _coordinates.absolute_to_world(center_abs)
		var side := cell_m * clampf(sqrt(coverage), 0.08, 0.95)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(side, 1.0, side)), center_world + Vector3(0, 0.08, 0)))
	instance.multimesh = mm
	instance.visible = true

func _remove_batch(key: String) -> void:
	if not _batches.has(key):
		return
	var node := _batches[key] as Node
	_batches.erase(key)
	if node != null:
		node.free()

func _clear_batches() -> void:
	for node_value in _batches.values():
		var node := node_value as Node
		if node != null:
			node.free()
	_batches.clear()

func _renderer_memory_pressure() -> float:
	return LodPolicy.ram_pressure(int(Performance.get_monitor(Performance.MEMORY_STATIC)), ram_target_bytes, ram_hard_bytes)

func debug_snapshot() -> Dictionary:
	return {
		"active": _enabled,
		"cache_ready": _cache_ready,
		"coverage_ready": _coverage_ready,
		"samples": _last_samples,
		"masked_by_detail": _masked_samples,
		"batches": _batches.size(),
		"max_batches": max_batches,
		"level": _last_level,
		"cell_m": _last_cell_m,
		"meters_per_pixel": _last_mpp,
		"build_ms": _last_build_ms,
		"density": density_scale,
		"sample_budget": base_sample_budget,
		"ram_pressure": _last_pressure
	}
