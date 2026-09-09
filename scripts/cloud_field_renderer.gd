extends MultiMeshInstance3D

## Renders deterministic cloud state as one lightweight MultiMesh of bounded 3D puffs.
##
## Dependencies:
## - Consumes cloud_field_model.gd output.
## - Receives camera view state explicitly from composition.
## - Uses normal Godot scene lighting, so #66 can move the shared sun without cloud astronomy.

const CloudFieldModelScript = preload("res://scripts/cloud_field_model.gd")
const MAX_PUFF_INSTANCES: int = 7200
const DEFAULT_COVERAGE: float = 0.64
const INSIDE_FADE_MIN_ALPHA: float = 0.10
const INSIDE_FADE_START: float = 1.30
const MAX_LOCAL_PUFF_WIDTH_M: float = 36000.0
const MAX_PUFF_ASPECT: float = 3.2

@export_range(0.0, 1.0, 0.01) var coverage: float = DEFAULT_COVERAGE
@export var field_seed: int = 700031

var _model = CloudFieldModelScript.new()
var _clouds: Array[Dictionary] = []
var _puffs: Array[Dictionary] = []
var _simulation_seconds: float = 0.0
var _view_focus: Vector3 = Vector3.ZERO
var _camera_distance_m: float = 800000.0
var _camera_world_position: Vector3 = Vector3(0.0, 800000.0, 0.0)
var _last_cell := Vector2i(2147483647, 2147483647)
var _last_lod: int = -1
var _resources_ready: bool = false
var _faded_puff_count: int = 0
var _max_puff_width_m: float = 0.0
var _max_formation_size_m: float = 0.0

func _ready() -> void:
	_create_render_resources()
	_resources_ready = true
	_rebuild_if_needed(true)

func _process(delta: float) -> void:
	_simulation_seconds += maxf(0.0, delta)
	_update_instance_transforms()

func set_view_state(focus_world: Vector3, camera_distance_m: float, camera_world_position: Vector3) -> void:
	_view_focus = focus_world
	_camera_distance_m = maxf(1.0, camera_distance_m)
	_camera_world_position = camera_world_position
	if _resources_ready:
		_rebuild_if_needed(false)
		_update_instance_transforms()

func set_simulation_seconds(simulation_seconds: float) -> void:
	_simulation_seconds = maxf(0.0, simulation_seconds)
	if _resources_ready:
		_update_instance_transforms()

func set_coverage(new_coverage: float) -> void:
	var clamped: float = _model.normalized_coverage(new_coverage)
	if is_equal_approx(clamped, coverage):
		return
	coverage = clamped
	if _resources_ready:
		_rebuild_if_needed(true)

func get_render_stats() -> Dictionary:
	return {
		"cloud_count": _clouds.size(),
		"puff_instance_count": _puffs.size(),
		"max_puff_instances": MAX_PUFF_INSTANCES,
		"faded_puff_count": _faded_puff_count,
		"lod": _lod_for_distance(_camera_distance_m),
		"coverage": coverage,
		"max_puff_width_m": _max_puff_width_m,
		"max_formation_size_m": _max_formation_size_m,
	}

func _create_render_resources() -> void:
	var puff_mesh := SphereMesh.new()
	puff_mesh.radius = 0.5
	puff_mesh.height = 1.0
	puff_mesh.radial_segments = 8
	puff_mesh.rings = 4

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.98, 0.99, 1.0, 0.90)
	material.roughness = 1.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	puff_mesh.material = material

	var cloud_multimesh := MultiMesh.new()
	cloud_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	cloud_multimesh.use_colors = true
	cloud_multimesh.mesh = puff_mesh
	cloud_multimesh.instance_count = 0
	multimesh = cloud_multimesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _rebuild_if_needed(force: bool) -> void:
	var center_cell := Vector2i(
		int(floor(_view_focus.x / CloudFieldModelScript.CELL_SIZE_M)),
		int(floor(_view_focus.z / CloudFieldModelScript.CELL_SIZE_M))
	)
	var lod: int = _lod_for_distance(_camera_distance_m)
	if not force and center_cell == _last_cell and lod == _last_lod:
		return
	_last_cell = center_cell
	_last_lod = lod
	_rebuild_clouds(center_cell, lod)

func _rebuild_clouds(center_cell: Vector2i, lod: int) -> void:
	_clouds.clear()
	_puffs.clear()
	_max_puff_width_m = 0.0
	_max_formation_size_m = 0.0
	var radius: int = _cell_radius_for_lod(lod)

	for cell_y in range(center_cell.y - radius, center_cell.y + radius + 1):
		for cell_x in range(center_cell.x - radius, center_cell.x + radius + 1):
			var generated: Array[Dictionary] = _model.generate_cell(Vector2i(cell_x, cell_y), coverage, field_seed)
			for cloud in generated:
				var puff_count: int = _puffs_for_cloud(cloud, lod)
				if _puffs.size() + puff_count > MAX_PUFF_INSTANCES:
					break
				var cloud_index: int = _clouds.size()
				_clouds.append(cloud)
				_max_formation_size_m = maxf(_max_formation_size_m, float(cloud["size_m"]))
				_append_cloud_puffs(cloud_index, cloud, puff_count)
			if _puffs.size() >= MAX_PUFF_INSTANCES:
				break
		if _puffs.size() >= MAX_PUFF_INSTANCES:
			break

	multimesh.instance_count = _puffs.size()
	_update_instance_transforms()

func _append_cloud_puffs(cloud_index: int, cloud: Dictionary, puff_count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cloud["puff_seed"])
	var size_m: float = float(cloud["size_m"])
	var thickness_m: float = float(cloud["thickness_m"])
	var profile_name := String(cloud["profile"])
	var footprint_radius: float = _footprint_radius_fraction(profile_name) * size_m
	var nominal_width: float = _nominal_lobe_width(profile_name, size_m, thickness_m)

	for puff_index in range(puff_count):
		var angle: float = rng.randf_range(0.0, TAU)
		var radial: float = 0.0 if puff_index == 0 else sqrt(rng.randf()) * footprint_radius
		var vertical_layer: float = rng.randf_range(-0.38, 0.48)
		if puff_index % 5 == 0:
			vertical_layer = rng.randf_range(0.18, 0.55)
		elif puff_index % 7 == 0:
			vertical_layer = rng.randf_range(-0.48, -0.14)
		var offset := Vector3(
			cos(angle) * radial,
			vertical_layer * thickness_m,
			sin(angle) * radial
		)

		var height_m: float = maxf(300.0, thickness_m * rng.randf_range(0.42, 0.78))
		var width_m: float = nominal_width * rng.randf_range(0.72, 1.18)
		width_m = minf(width_m, MAX_LOCAL_PUFF_WIDTH_M)
		width_m = minf(width_m, height_m * MAX_PUFF_ASPECT)
		width_m = maxf(width_m, minf(700.0, size_m * 0.35))
		_max_puff_width_m = maxf(_max_puff_width_m, width_m)

		_puffs.append({
			"cloud_index": cloud_index,
			"offset": offset,
			"scale": Vector3(width_m, height_m, width_m),
		})

func _nominal_lobe_width(profile_name: String, size_m: float, thickness_m: float) -> float:
	match profile_name:
		"small_cumulus":
			return minf(size_m * 0.52, 1800.0)
		"medium_cumulus":
			return minf(size_m * 0.34, 3600.0)
		"large_low_mid":
			return minf(size_m * 0.22, 6500.0)
		"giant_cloud_bank":
			return minf(size_m * 0.11, 14000.0)
		"continental_cloud_bank":
			return minf(size_m * 0.035, 32000.0)
		_:
			return minf(size_m * 0.35, thickness_m * MAX_PUFF_ASPECT)

func _footprint_radius_fraction(profile_name: String) -> float:
	match profile_name:
		"small_cumulus":
			return 0.28
		"medium_cumulus":
			return 0.34
		"large_low_mid":
			return 0.39
		"giant_cloud_bank":
			return 0.44
		"continental_cloud_bank":
			return 0.48
		_:
			return 0.32

func _puffs_for_cloud(cloud: Dictionary, lod: int) -> int:
	var profile_name := String(cloud["profile"])
	match profile_name:
		"continental_cloud_bank":
			return 24 if lod == 0 else (56 if lod == 1 else 96)
		"giant_cloud_bank":
			return 10 if lod == 0 else (24 if lod == 1 else 40)
		"large_low_mid":
			return 5 if lod == 0 else (12 if lod == 1 else 18)
		"medium_cumulus":
			return 3 if lod == 0 else (8 if lod == 1 else 12)
		_:
			return 3 if lod == 0 else (6 if lod == 1 else 9)

func _update_instance_transforms() -> void:
	if multimesh == null or _puffs.is_empty():
		return
	var moved_positions: Array[Vector3] = []
	moved_positions.resize(_clouds.size())
	for cloud_index in range(_clouds.size()):
		moved_positions[cloud_index] = _model.position_at(_clouds[cloud_index], _simulation_seconds)

	_faded_puff_count = 0
	for puff_index in range(_puffs.size()):
		var puff: Dictionary = _puffs[puff_index]
		var cloud_index: int = int(puff["cloud_index"])
		var offset: Vector3 = puff["offset"]
		var scale_value: Vector3 = puff["scale"]
		var center: Vector3 = moved_positions[cloud_index] + offset
		var transform := Transform3D(Basis().scaled(scale_value), center)
		multimesh.set_instance_transform(puff_index, transform)
		var alpha: float = _camera_alpha(center, scale_value)
		if alpha < 0.89:
			_faded_puff_count += 1
		multimesh.set_instance_color(puff_index, Color(1.0, 1.0, 1.0, alpha))

func _camera_alpha(center: Vector3, scale_value: Vector3) -> float:
	var half_extents := Vector3(
		maxf(1.0, scale_value.x * 0.5),
		maxf(1.0, scale_value.y * 0.5),
		maxf(1.0, scale_value.z * 0.5)
	)
	var relative := _camera_world_position - center
	var normalized_distance := Vector3(
		relative.x / half_extents.x,
		relative.y / half_extents.y,
		relative.z / half_extents.z
	).length()
	if normalized_distance >= INSIDE_FADE_START:
		return 1.0
	var fade: float = smoothstep(0.20, INSIDE_FADE_START, normalized_distance)
	return lerpf(INSIDE_FADE_MIN_ALPHA, 1.0, fade)

func _lod_for_distance(distance_m: float) -> int:
	if distance_m >= 600000.0:
		return 0
	if distance_m >= 220000.0:
		return 1
	return 2

func _cell_radius_for_lod(lod: int) -> int:
	match lod:
		0:
			return 4
		1:
			return 3
		_:
			return 2
