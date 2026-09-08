extends MultiMeshInstance3D

## Renders deterministic cloud state as one lightweight MultiMesh of 3D puffs.
##
## Dependencies:
## - Consumes cloud_field_model.gd output.
## - Receives camera view state explicitly from composition.
## - Uses normal Godot scene lighting, so #66 can move the shared sun without cloud astronomy.

const CloudFieldModelScript = preload("res://scripts/cloud_field_model.gd")
const MAX_PUFF_INSTANCES: int = 2200
const DEFAULT_COVERAGE: float = 0.64
const INSIDE_FADE_MIN_ALPHA: float = 0.10
const INSIDE_FADE_START: float = 1.30

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
	}

func _create_render_resources() -> void:
	var puff_mesh := SphereMesh.new()
	puff_mesh.radius = 0.5
	puff_mesh.height = 1.0
	puff_mesh.radial_segments = 8
	puff_mesh.rings = 4

	# Keep cloud lighting deliberately conventional: the same DirectionalLight3D
	# used by the world lights the puff normals. Per-instance vertex color only
	# changes opacity for camera-inside fading; it does not own any sun logic.
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
	var radius: int = _cell_radius_for_lod(lod)
	var puffs_per_cloud: int = _puffs_per_cloud_for_lod(lod)

	for cell_y in range(center_cell.y - radius, center_cell.y + radius + 1):
		for cell_x in range(center_cell.x - radius, center_cell.x + radius + 1):
			var generated: Array[Dictionary] = _model.generate_cell(Vector2i(cell_x, cell_y), coverage, field_seed)
			for cloud in generated:
				if _puffs.size() + puffs_per_cloud > MAX_PUFF_INSTANCES:
					break
				var cloud_index: int = _clouds.size()
				_clouds.append(cloud)
				_append_cloud_puffs(cloud_index, cloud, puffs_per_cloud)
			if _puffs.size() + puffs_per_cloud > MAX_PUFF_INSTANCES:
				break
		if _puffs.size() + puffs_per_cloud > MAX_PUFF_INSTANCES:
			break

	multimesh.instance_count = _puffs.size()
	_update_instance_transforms()

func _append_cloud_puffs(cloud_index: int, cloud: Dictionary, puff_count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cloud["puff_seed"])
	var size_m: float = float(cloud["size_m"])
	var thickness_m: float = float(cloud["thickness_m"])
	for puff_index in range(puff_count):
		var offset := Vector3.ZERO
		var width_m: float
		var height_m: float
		if puff_index == 0:
			width_m = size_m * 0.50
			height_m = thickness_m * 0.82
		else:
			var angle: float = rng.randf_range(0.0, TAU)
			var radius: float = rng.randf_range(0.08, 0.34) * size_m
			var vertical_layer: float = rng.randf_range(-0.42, 0.46)
			if puff_index % 3 == 0:
				vertical_layer = rng.randf_range(0.18, 0.52)
			elif puff_index % 4 == 0:
				vertical_layer = rng.randf_range(-0.48, -0.16)
			offset = Vector3(
				cos(angle) * radius,
				vertical_layer * thickness_m,
				sin(angle) * radius
			)
			width_m = size_m * rng.randf_range(0.25, 0.44)
			height_m = thickness_m * rng.randf_range(0.48, 0.76)
		_puffs.append({
			"cloud_index": cloud_index,
			"offset": offset,
			"scale": Vector3(width_m, height_m, width_m),
		})

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

func _puffs_per_cloud_for_lod(lod: int) -> int:
	match lod:
		0:
			# At Sweden overview scale, silhouette/size carries the cloud shape.
			# Three puffs lets the fixed GPU budget show many more distinct groups.
			return 3
		1:
			return 6
		_:
			return 9
