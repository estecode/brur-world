extends Node3D
class_name CityLightRenderer

## Renders nighttime urban glow and batched city-light points from CityLightModel data.
##
## Dependencies:
## - Consumes CityLightModel presentation data.
## - Reads solar state from an explicitly configured SunRuntimeController.
## - Reads camera distance from an explicitly configured CameraRig for presentation LOD only.

const CityLightModelScript = preload("res://scripts/city_light_model.gd")
const MAX_LIGHT_POINTS: int = 12000
const POINTS_MAX_DISTANCE_M: float = 180000.0
const POINT_DIAMETER_M: float = 190.0
const POINT_HEIGHT_M: float = 120.0
const GLOW_ALPHA: float = 0.42

@export_node_path("Node") var sun_controller_path: NodePath
@export_node_path("Node3D") var camera_rig_path: NodePath

var _model = CityLightModelScript.new()
var _sun_controller: Node
var _camera_rig: Node3D
var _glow_instance: MeshInstance3D
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
	if _points_instance != null and _points_instance.multimesh != null:
		_points_instance.multimesh.instance_count = 0

func add_urban_triangle(a: Vector3, b: Vector3, c: Vector3) -> void:
	_model.add_urban_triangle(a, b, c)

func finish_urban_data() -> void:
	var points: Array[Vector3] = _model.light_points(MAX_LIGHT_POINTS)
	var lights_multimesh := _points_instance.multimesh
	lights_multimesh.instance_count = points.size()
	var point_basis := Basis.IDENTITY.scaled(Vector3(POINT_DIAMETER_M, POINT_HEIGHT_M, POINT_DIAMETER_M))
	for index in range(points.size()):
		var transform := Transform3D(point_basis, points[index] + Vector3(0.0, POINT_HEIGHT_M * 0.5, 0.0))
		lights_multimesh.set_instance_transform(index, transform)
	_data_ready = true
	_update_visibility()

func set_urban_mesh(mesh: Mesh) -> void:
	_glow_instance.mesh = mesh

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
	var point_count := 0
	if _points_instance != null and _points_instance.multimesh != null:
		point_count = _points_instance.multimesh.instance_count
	return {
		"night_intensity": _night_intensity,
		"source_cell_count": _model.source_cell_count(),
		"point_count": point_count,
		"max_point_count": MAX_LIGHT_POINTS,
		"glow_visible": _glow_instance != null and _glow_instance.visible,
		"points_visible": _points_instance != null and _points_instance.visible,
	}

func _create_render_resources() -> void:
	_glow_instance = MeshInstance3D.new()
	_glow_instance.name = "UrbanGlow"
	_glow_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow_material = StandardMaterial3D.new()
	_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_glow_material.emission_enabled = true
	_glow_instance.material_override = _glow_material
	add_child(_glow_instance)

	var point_mesh := SphereMesh.new()
	point_mesh.radius = 0.5
	point_mesh.height = 1.0
	point_mesh.radial_segments = 6
	point_mesh.rings = 3
	_point_material = StandardMaterial3D.new()
	_point_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_point_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_point_material.emission_enabled = true
	point_mesh.material = _point_material

	var lights_multimesh := MultiMesh.new()
	lights_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	lights_multimesh.mesh = point_mesh
	lights_multimesh.instance_count = 0

	_points_instance = MultiMeshInstance3D.new()
	_points_instance.name = "LocalLightPoints"
	_points_instance.multimesh = lights_multimesh
	_points_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_points_instance)
	_apply_material_intensity()

func _apply_material_intensity() -> void:
	if _glow_material == null or _point_material == null:
		return
	var glow_color := Color(1.0, 0.58, 0.20, GLOW_ALPHA * _night_intensity)
	_glow_material.albedo_color = glow_color
	_glow_material.emission = Color(1.0, 0.42, 0.12)
	_glow_material.emission_energy_multiplier = 1.65 * _night_intensity
	var point_color := Color(1.0, 0.72, 0.34, 0.92 * _night_intensity)
	_point_material.albedo_color = point_color
	_point_material.emission = Color(1.0, 0.56, 0.20)
	_point_material.emission_energy_multiplier = 2.4 * _night_intensity

func _update_visibility() -> void:
	if _glow_instance == null or _points_instance == null:
		return
	var night_visible := _data_ready and _night_intensity > 0.001
	_glow_instance.visible = night_visible and _glow_instance.mesh != null
	var camera_distance := INF
	if _camera_rig != null and _camera_rig.has_method("get_distance"):
		camera_distance = float(_camera_rig.call("get_distance"))
	_points_instance.visible = night_visible and camera_distance <= POINTS_MAX_DISTANCE_M

func _on_solar_state_changed(solar_state: Dictionary) -> void:
	apply_solar_state(solar_state)
