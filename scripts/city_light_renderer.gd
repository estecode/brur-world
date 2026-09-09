extends Node3D
class_name CityLightRenderer

## Renders nighttime urban glow clusters and batched local city-light points from CityLightModel data.
##
## Dependencies:
## - Consumes CityLightModel presentation data.
## - Reads solar state from an explicitly configured SunRuntimeController.
## - Reads camera distance from an explicitly configured CameraRig for presentation LOD only.

const CityLightModelScript = preload("res://scripts/city_light_model.gd")
const MAX_GLOW_CLUSTERS: int = 6000
const MAX_LOCAL_LIGHTS: int = 12000
const LOCAL_POINTS_MAX_DISTANCE_M: float = 220000.0
const GLOW_MIN_DISTANCE_M: float = 140000.0
const GLOW_DIAMETER_M: float = 1800.0
const GLOW_HEIGHT_M: float = 35.0
const LOCAL_POINT_DIAMETER_M: float = 85.0
const LOCAL_POINT_HEIGHT_M: float = 45.0

@export_node_path("Node") var sun_controller_path: NodePath
@export_node_path("Node3D") var camera_rig_path: NodePath

var _model = CityLightModelScript.new()
var _sun_controller: Node
var _camera_rig: Node3D
var _glow_instance: MultiMeshInstance3D
var _points_instance: MultiMeshInstance3D
var _glow_material: StandardMaterial3D
var _point_material: StandardMaterial3D
var _night_intensity: float = 0.0
var _base_height: float = 0.0
var _data_ready: bool = false

func _ready() -> void:
	_create_render_resources()
	_sun_controller = get_node_or_null(sun_controller_path)
	_camera_rig = get_node_or_null(camera_rig_path) as Node3D
	if _sun_controller != null and _sun_controller.has_signal("solar_state_changed"):
		_sun_controller.connect("solar_state_changed", _on_solar_state_changed)
	if _sun_controller != null and _sun_controller.has_method("get_last_solar_state"):
		var state: Variant = _sun_controller.call("get_last_solar_state")
		if state is Dictionary:
			apply_solar_state(state as Dictionary)
	_update_visibility()

func _process(_delta: float) -> void:
	_update_visibility()

func begin_urban_data() -> void:
	_model.reset_distribution()
	_data_ready = false
	if _glow_instance != null and _glow_instance.multimesh != null:
		_glow_instance.multimesh.instance_count = 0
	if _points_instance != null and _points_instance.multimesh != null:
		_points_instance.multimesh.instance_count = 0

func add_urban_triangle(a: Vector3, b: Vector3, c: Vector3) -> void:
	_model.add_urban_triangle(a, b, c)

func finish_urban_data() -> void:
	_build_multimesh(
		_glow_instance.multimesh,
		_model.overview_points(MAX_GLOW_CLUSTERS),
		Vector3(GLOW_DIAMETER_M, GLOW_HEIGHT_M, GLOW_DIAMETER_M)
	)
	_build_multimesh(
		_points_instance.multimesh,
		_model.local_light_points(MAX_LOCAL_LIGHTS),
		Vector3(LOCAL_POINT_DIAMETER_M, LOCAL_POINT_HEIGHT_M, LOCAL_POINT_DIAMETER_M)
	)
	_data_ready = true
	_update_visibility()

func set_urban_mesh(_mesh: Mesh) -> void:
	# Kept as a compatibility hook for the current world composition. The polygon
	# itself is intentionally not rendered as light; that looked like a GIS fill
	# rather than a city at night. Both LODs now derive from the same urban cells.
	pass

func set_base_height(height_m: float) -> void:
	_base_height = height_m
	position.y = _base_height

func apply_solar_state(solar_state: Dictionary) -> void:
	if not bool(solar_state.get("valid", false)):
		return
	_night_intensity = _model.night_intensity(float(solar_state.get("elevation_deg", 90.0)))
	_apply_material_intensity()
	_update_visibility()

func get_render_stats() -> Dictionary:
	return {
		"night_intensity": _night_intensity,
		"source_cell_count": _model.source_cell_count(),
		"glow_count": _instance_count(_glow_instance),
		"point_count": _instance_count(_points_instance),
		"max_glow_count": MAX_GLOW_CLUSTERS,
		"max_point_count": MAX_LOCAL_LIGHTS,
		"glow_visible": _glow_instance != null and _glow_instance.visible,
		"points_visible": _points_instance != null and _points_instance.visible,
	}

func _create_render_resources() -> void:
	_glow_material = StandardMaterial3D.new()
	_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_material.emission_enabled = true
	_glow_instance = _create_multimesh_instance("UrbanGlowClusters", _glow_material, 8, 4)
	add_child(_glow_instance)

	_point_material = StandardMaterial3D.new()
	_point_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_point_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_point_material.emission_enabled = true
	_points_instance = _create_multimesh_instance("LocalLightPoints", _point_material, 6, 3)
	add_child(_points_instance)
	_apply_material_intensity()

func _create_multimesh_instance(name_value: String, material: StandardMaterial3D, radial_segments: int, rings: int) -> MultiMeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = radial_segments
	mesh.rings = rings
	mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = 0
	var instance := MultiMeshInstance3D.new()
	instance.name = name_value
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance

func _build_multimesh(multimesh: MultiMesh, points: Array[Vector3], scale_value: Vector3) -> void:
	multimesh.instance_count = points.size()
	var basis := Basis.IDENTITY.scaled(scale_value)
	for index in range(points.size()):
		var transform := Transform3D(basis, points[index] + Vector3(0.0, scale_value.y * 0.5, 0.0))
		multimesh.set_instance_transform(index, transform)

func _apply_material_intensity() -> void:
	if _glow_material == null or _point_material == null:
		return
	var glow_alpha := 0.18 * _night_intensity
	_glow_material.albedo_color = Color(1.0, 0.52, 0.16, glow_alpha)
	_glow_material.emission = Color(1.0, 0.38, 0.10)
	_glow_material.emission_energy_multiplier = 0.85 * _night_intensity
	var point_alpha := 0.92 * _night_intensity
	_point_material.albedo_color = Color(1.0, 0.78, 0.42, point_alpha)
	_point_material.emission = Color(1.0, 0.60, 0.22)
	_point_material.emission_energy_multiplier = 2.6 * _night_intensity

func _update_visibility() -> void:
	if _glow_instance == null or _points_instance == null:
		return
	var night_visible := _data_ready and _night_intensity > 0.001
	var camera_distance := INF
	if _camera_rig != null and _camera_rig.has_method("get_distance"):
		camera_distance = float(_camera_rig.call("get_distance"))
	_glow_instance.visible = night_visible and camera_distance >= GLOW_MIN_DISTANCE_M
	_points_instance.visible = night_visible and camera_distance <= LOCAL_POINTS_MAX_DISTANCE_M

func _instance_count(instance: MultiMeshInstance3D) -> int:
	if instance == null or instance.multimesh == null:
		return 0
	return instance.multimesh.instance_count

func _on_solar_state_changed(solar_state: Dictionary) -> void:
	apply_solar_state(solar_state)
