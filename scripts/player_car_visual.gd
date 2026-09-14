extends Node3D
class_name PlayerCarVisual

## Builds the shared player-car presentation used in both Map and Drive views.
##
## Dependencies:
## - Presentation-only geometry; it does not own vehicle state, physics, routing, camera, or coordinates.
## - Map presentation may enable overlay rendering while Drive uses normal depth-tested materials.

const CAR_LENGTH_M := 4.5
const CAR_WIDTH_M := 1.8
const CABIN_LENGTH_M := 2.45
const CABIN_WIDTH_M := 1.52

var _materials: Array[StandardMaterial3D] = []

func _ready() -> void:
	if get_child_count() == 0:
		_build_visuals()

func set_overlay_mode(enabled: bool) -> void:
	if get_child_count() == 0:
		_build_visuals()
	for material in _materials:
		material.no_depth_test = enabled
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if enabled else BaseMaterial3D.SHADING_MODE_PER_PIXEL

static func physical_size_m() -> Vector2:
	return Vector2(CAR_WIDTH_M, CAR_LENGTH_M)

func _build_visuals() -> void:
	_mesh_box("Body", Vector3(CAR_WIDTH_M, 0.28, CAR_LENGTH_M), Vector3(0.0, 0.14, 0.0), Color(0.92, 0.92, 0.94))
	_mesh_box("Cabin", Vector3(CABIN_WIDTH_M, 0.24, CABIN_LENGTH_M), Vector3(0.0, 0.38, 0.10), Color(0.72, 0.75, 0.79))
	_mesh_box("Windshield", Vector3(1.38, 0.04, 0.62), Vector3(0.0, 0.515, -0.62), Color(0.10, 0.16, 0.20))
	_mesh_box("RearWindow", Vector3(1.34, 0.04, 0.54), Vector3(0.0, 0.515, 0.73), Color(0.16, 0.21, 0.24))

func _mesh_box(node_name: String, size: Vector3, local_position: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = local_position
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	instance.material_override = material
	_materials.append(material)
	add_child(instance)
	return instance
