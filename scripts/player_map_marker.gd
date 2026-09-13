extends Node3D
class_name PlayerMapMarker

## Presents the player as a recognizable top-down passenger car in Map mode.
##
## Dependencies:
## - Receives camera distance and vehicle heading explicitly from GpsRouteLayer.
## - Owns presentation meshes only; it never changes vehicle simulation dimensions.

const CAR_LENGTH_M := 4.5
const CAR_WIDTH_M := 1.8
const CABIN_LENGTH_M := 2.45
const CABIN_WIDTH_M := 1.52
const NEAR_DISTANCE_M := 250.0
const MAX_VISUAL_SCALE := 28.0

var _body: MeshInstance3D
var _cabin: MeshInstance3D
var _windshield: MeshInstance3D
var _rear_window: MeshInstance3D

func _ready() -> void:
	if _body == null:
		_build_visuals()

func set_view_state(camera_distance_m: float, driving_view: bool, vehicle_heading_rad: float) -> void:
	visible = not driving_view
	rotation.y = vehicle_heading_rad
	var visual_scale := scale_for_distance(camera_distance_m)
	scale = Vector3.ONE * visual_scale

static func scale_for_distance(camera_distance_m: float) -> float:
	if camera_distance_m <= NEAR_DISTANCE_M:
		return 1.0
	return clampf(pow(camera_distance_m / NEAR_DISTANCE_M, 0.45), 1.0, MAX_VISUAL_SCALE)

static func physical_size_m() -> Vector2:
	return Vector2(CAR_WIDTH_M, CAR_LENGTH_M)

func _build_visuals() -> void:
	_body = _mesh_box("Body", Vector3(CAR_WIDTH_M, 0.28, CAR_LENGTH_M), Vector3(0.0, 0.14, 0.0), Color(0.92, 0.92, 0.94))
	_cabin = _mesh_box("Cabin", Vector3(CABIN_WIDTH_M, 0.24, CABIN_LENGTH_M), Vector3(0.0, 0.38, 0.10), Color(0.72, 0.75, 0.79))
	_windshield = _mesh_box("Windshield", Vector3(1.38, 0.04, 0.62), Vector3(0.0, 0.515, -0.62), Color(0.10, 0.16, 0.20))
	_rear_window = _mesh_box("RearWindow", Vector3(1.34, 0.04, 0.54), Vector3(0.0, 0.515, 0.73), Color(0.16, 0.21, 0.24))

func _mesh_box(node_name: String, size: Vector3, local_position: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = local_position
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	instance.material_override = material
	add_child(instance)
	return instance
