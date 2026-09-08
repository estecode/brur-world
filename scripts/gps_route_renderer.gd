class_name GpsRouteRenderer
extends Node3D

## Renders GPS route geometry and the snapped destination marker.
##
## Dependencies:
## - Consumes structured route response data and a caller-supplied absolute->world converter.
## - Has no route model, TCP, process, input or UI dependency.

var _to_world: Callable
var _route_mesh_instance: MeshInstance3D
var _route_material: StandardMaterial3D
var _target_marker: MeshInstance3D
var _rendered_point_count: int = 0

func _ready() -> void:
	_ensure_visuals()

func setup(to_world: Callable) -> void:
	_to_world = to_world
	_ensure_visuals()

func apply_response(response: Dictionary) -> bool:
	if not bool(response.get("success", false)):
		clear()
		return false
	var points_value: Variant = response.get("points", [])
	if typeof(points_value) != TYPE_ARRAY:
		clear()
		return false
	var points: Array = points_value as Array
	if not draw_route(points):
		clear()
		return false
	var target_value: Variant = response.get("target_snap", [])
	if typeof(target_value) == TYPE_ARRAY:
		show_target(target_value as Array)
	return true

func draw_route(points: Array) -> bool:
	_ensure_visuals()
	if not _to_world.is_valid():
		return false
	var vertices := PackedVector3Array()
	for value in points:
		if typeof(value) != TYPE_ARRAY:
			continue
		var pair: Array = value as Array
		if pair.size() < 2:
			continue
		var converted: Variant = _to_world.call(float(pair[0]), float(pair[1]))
		if typeof(converted) != TYPE_VECTOR3:
			continue
		var local: Vector3 = converted
		if not local.is_finite():
			continue
		vertices.append(Vector3(local.x, 0.0, local.z))
	_rendered_point_count = vertices.size()
	if vertices.size() < 2:
		_route_mesh_instance.mesh = null
		return false
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var route_mesh := ArrayMesh.new()
	route_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arrays)
	_route_mesh_instance.mesh = route_mesh
	return true

func show_target(target_snap: Array) -> bool:
	_ensure_visuals()
	if target_snap.size() < 2 or not _to_world.is_valid():
		_target_marker.visible = false
		return false
	var converted: Variant = _to_world.call(float(target_snap[0]), float(target_snap[1]))
	if typeof(converted) != TYPE_VECTOR3:
		_target_marker.visible = false
		return false
	var local: Vector3 = converted
	if not local.is_finite():
		_target_marker.visible = false
		return false
	_target_marker.position.x = local.x
	_target_marker.position.z = local.z
	_target_marker.visible = true
	return true

func clear() -> void:
	_ensure_visuals()
	_route_mesh_instance.mesh = null
	_target_marker.visible = false
	_rendered_point_count = 0

func update_height(camera_distance: float) -> void:
	_ensure_visuals()
	var spacing: float = clampf(camera_distance / 6000.0, 4.0, 240.0)
	var route_y: float = spacing * 7.0
	_route_mesh_instance.position.y = route_y
	_target_marker.position.y = route_y + maxf(90.0, spacing)
	var marker_scale: float = clampf(camera_distance / 30000.0, 1.0, 20.0)
	_target_marker.scale = Vector3.ONE * marker_scale

func route_height() -> float:
	_ensure_visuals()
	return _route_mesh_instance.position.y

func rendered_point_count() -> int:
	return _rendered_point_count

func _ensure_visuals() -> void:
	if _route_mesh_instance != null:
		return
	_route_mesh_instance = MeshInstance3D.new()
	_route_mesh_instance.name = "GpsRoute"
	_route_material = StandardMaterial3D.new()
	_route_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_route_material.albedo_color = Color(0.05, 0.75, 1.0)
	_route_material.no_depth_test = true
	_route_mesh_instance.material_override = _route_material
	add_child(_route_mesh_instance)

	_target_marker = MeshInstance3D.new()
	_target_marker.name = "GpsTarget"
	var sphere := SphereMesh.new()
	sphere.radius = 80.0
	sphere.height = 160.0
	_target_marker.mesh = sphere
	var marker_material := StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.albedo_color = Color(1.0, 0.35, 0.08)
	_target_marker.material_override = marker_material
	_target_marker.visible = false
	add_child(_target_marker)
