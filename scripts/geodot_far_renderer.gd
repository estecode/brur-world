extends Node3D
class_name GeoDotFarRenderer

const FarCache = preload("res://scripts/geodot_far_cache.gd")
const LodPolicy = preload("res://scripts/geodot_lod_policy.gd")

@export var enter_distance_m := 75000.0
@export var exit_distance_m := 60000.0
@export var target_screen_cell_px := 5.0
@export var base_sample_budget := 12000
@export var hard_sample_cap := 24000
@export var density_scale := 1.0

var _coordinates = null
var _camera_rig: Node = null
var _cache = FarCache.new()
var _instance: MultiMeshInstance3D = null
var _enabled := false
var _active := false
var _refresh_accum := 0.0
var _last_samples := 0
var _last_level := -1
var _last_cell_m := 0.0
var _last_mpp := 0.0
var _last_build_ms := 0.0

func setup(world_coordinates, camera_rig: Node, cache_path: String) -> Dictionary:
	_coordinates = world_coordinates; _camera_rig = camera_rig
	var opened := _cache.open(cache_path)
	if opened.get("ok", false) != true: return opened
	_instance = MultiMeshInstance3D.new(); _instance.name = "GeoDotFarAggregate"; add_child(_instance)
	_enabled = true; set_process(true); return opened

func shutdown() -> void:
	set_process(false); _enabled = false; _active = false; _cache.close()
	if _instance != null: _instance.free(); _instance = null
	_coordinates = null; _camera_rig = null

func _exit_tree() -> void: shutdown()

func set_tuning(values: Dictionary) -> void:
	if values.has("far_density"): density_scale = clampf(float(values.far_density), 0.05, 4.0)
	if values.has("far_pixel_budget"): base_sample_budget = clampi(int(values.far_pixel_budget), 500, hard_sample_cap)
	if values.has("far_tile_pixels"): target_screen_cell_px = clampf(float(values.far_tile_pixels), 1.0, 32.0)

func _process(delta: float) -> void:
	if not _enabled or _camera_rig == null: return
	_refresh_accum += delta
	if _refresh_accum < 0.25: return
	_refresh_accum = 0.0; _refresh()

func _refresh() -> void:
	if not _camera_rig.has_method("get_focus_world"): return
	var focus: Vector3 = _camera_rig.call("get_focus_world")
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera == null: return
	var distance := camera.global_position.distance_to(focus)
	if _active:
		_active = distance >= exit_distance_m
	else:
		_active = distance >= enter_distance_m
	visible = _active
	if not _active: return
	var bounds := _view_bounds(focus)
	var viewport := get_viewport().get_visible_rect().size
	_last_mpp = LodPolicy.meters_per_pixel(bounds, viewport)
	var desired_cell_m := maxf(2000.0, _last_mpp * target_screen_cell_px)
	_last_level = _cache.choose_level(desired_cell_m)
	if _last_level < 0: return
	var pressure := _renderer_memory_pressure()
	var budget := LodPolicy.sample_budget(base_sample_budget, density_scale * LodPolicy.quality_scale_for_pressure(pressure), hard_sample_cap)
	var started := Time.get_ticks_usec()
	var samples := _cache.query_bounds(bounds, _last_level, budget, density_scale)
	_publish(samples)
	_last_samples = samples.size(); _last_build_ms = float(Time.get_ticks_usec() - started) / 1000.0
	if not samples.is_empty(): _last_cell_m = float(samples[0].cell_m)

func _view_bounds(focus: Vector3) -> Rect2:
	var points: Array[Vector3] = []
	if _camera_rig.has_method("get_ground_view_corners"):
		var corners: Variant = _camera_rig.call("get_ground_view_corners")
		if typeof(corners) == TYPE_ARRAY or typeof(corners) == TYPE_PACKED_VECTOR3_ARRAY:
			for value in corners:
				if typeof(value) == TYPE_VECTOR3 and (value as Vector3).is_finite(): points.append(value)
	if points.is_empty(): points = [focus]
	var first: Vector2 = _coordinates.world_to_absolute(points[0]); var minp := first; var maxp := first
	for point in points:
		var absolute: Vector2 = _coordinates.world_to_absolute(point); minp.x=minf(minp.x,absolute.x); minp.y=minf(minp.y,absolute.y); maxp.x=maxf(maxp.x,absolute.x); maxp.y=maxf(maxp.y,absolute.y)
	return Rect2(minp, maxp-minp)

func _publish(samples: Array[Dictionary]) -> void:
	if _instance == null: return
	if samples.is_empty(): _instance.multimesh = null; return
	var quad := QuadMesh.new(); quad.orientation = PlaneMesh.FACE_Y; quad.size = Vector2.ONE
	var material := StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color=Color(0.32,0.33,0.34,0.72); material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; material.cull_mode=BaseMaterial3D.CULL_DISABLED
	quad.material = material
	var mm := MultiMesh.new(); mm.transform_format=MultiMesh.TRANSFORM_3D; mm.instance_count=samples.size(); mm.mesh=quad
	for index in range(samples.size()):
		var sample: Dictionary = samples[index]; var cell_m := float(sample.cell_m); var coverage := clampf(float(sample.coverage) * density_scale, 0.0, 1.0)
		var center_abs := Vector2((float(sample.x)+0.5)*cell_m,(float(sample.y)+0.5)*cell_m); var center_world: Vector3 = _coordinates.absolute_to_world(center_abs)
		var side := cell_m * clampf(sqrt(coverage), 0.08, 0.95)
		mm.set_instance_transform(index, Transform3D(Basis().scaled(Vector3(side,1.0,side)), center_world + Vector3(0,0.08,0)))
	_instance.multimesh = mm

func _renderer_memory_pressure() -> float:
	# Godot exposes process-wide static memory. The tuning panel supplies target/hard
	# renderer budgets; until attribution is exact, this is intentionally conservative.
	return 0.0

func debug_snapshot() -> Dictionary:
	return {"active":_active,"samples":_last_samples,"level":_last_level,"cell_m":_last_cell_m,"meters_per_pixel":_last_mpp,"build_ms":_last_build_ms,"density":density_scale,"sample_budget":base_sample_budget}
