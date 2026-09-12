class_name GpsRouteRenderer
extends Node3D

## Renders GPS route geometry as a camera-readable outlined ribbon and the snapped destination marker.
##
## Dependencies:
## - Consumes structured route response data and a caller-supplied absolute->world converter.
## - Receives the current road-surface presentation height from GPS composition.
## - Has no route model, TCP, process, input or UI dependency.

const ROUTE_OUTLINE_PRIORITY := 100
const ROUTE_CORE_PRIORITY := 101
const DRIVE_ROUTE_CLEARANCE_M := 0.08

var _to_world: Callable
var _route_outline_instance: MeshInstance3D
var _route_outline_material: StandardMaterial3D
var _route_mesh_instance: MeshInstance3D
var _route_material: StandardMaterial3D
var _target_marker: MeshInstance3D
var _route_points := PackedVector3Array()
var _rendered_point_count := 0
var _ribbon_width_m := 14.0

func _ready() -> void: _ensure_visuals()
func setup(to_world: Callable) -> void:
	_to_world = to_world
	_ensure_visuals()

func apply_response(response: Dictionary) -> bool:
	if not bool(response.get("success", false)):
		clear(); return false
	var points_value: Variant = response.get("points", [])
	if typeof(points_value) != TYPE_ARRAY or not draw_route(points_value as Array):
		clear(); return false
	var target_value: Variant = response.get("target_snap", [])
	if typeof(target_value) == TYPE_ARRAY: show_target(target_value as Array)
	return true

func draw_route(points: Array) -> bool:
	_ensure_visuals()
	if not _to_world.is_valid(): return false
	_route_points = PackedVector3Array()
	for value in points:
		if typeof(value) != TYPE_ARRAY: continue
		var pair := value as Array
		if pair.size() < 2: continue
		var converted: Variant = _to_world.call(float(pair[0]), float(pair[1]))
		if typeof(converted) != TYPE_VECTOR3: continue
		var local: Vector3 = converted
		if local.is_finite(): _route_points.append(Vector3(local.x, 0.0, local.z))
	_rendered_point_count = _route_points.size()
	if _route_points.size() < 2:
		_route_outline_instance.mesh = null
		_route_mesh_instance.mesh = null
		return false
	_rebuild_ribbon()
	return true

func _rebuild_ribbon() -> void:
	if _route_points.size() < 2:
		_route_outline_instance.mesh = null
		_route_mesh_instance.mesh = null
		return
	_route_outline_instance.mesh = _build_ribbon_mesh(outline_width_m())
	_route_mesh_instance.mesh = _build_ribbon_mesh(_ribbon_width_m)

func _build_ribbon_mesh(width_m: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var half_width := width_m * 0.5
	for i in range(_route_points.size()):
		var tangent: Vector3
		if i == 0: tangent = _route_points[1] - _route_points[0]
		elif i == _route_points.size() - 1: tangent = _route_points[i] - _route_points[i - 1]
		else: tangent = _route_points[i + 1] - _route_points[i - 1]
		tangent.y = 0.0
		if tangent.length_squared() < 0.000001: tangent = Vector3.FORWARD
		tangent = tangent.normalized()
		var side := Vector3(-tangent.z, 0.0, tangent.x) * half_width
		vertices.append(_route_points[i] - side)
		vertices.append(_route_points[i] + side)
		if i > 0:
			var base := i * 2
			indices.append_array(PackedInt32Array([base - 2, base - 1, base, base - 1, base + 1, base]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func show_target(target_snap: Array) -> bool:
	_ensure_visuals()
	if target_snap.size() < 2 or not _to_world.is_valid(): _target_marker.visible = false; return false
	var converted: Variant = _to_world.call(float(target_snap[0]), float(target_snap[1]))
	if typeof(converted) != TYPE_VECTOR3: _target_marker.visible = false; return false
	var local: Vector3 = converted
	if not local.is_finite(): _target_marker.visible = false; return false
	_target_marker.position.x = local.x
	_target_marker.position.z = local.z
	_target_marker.visible = true
	return true

func clear() -> void:
	_ensure_visuals()
	_route_outline_instance.mesh = null
	_route_mesh_instance.mesh = null
	_target_marker.visible = false
	_route_points = PackedVector3Array()
	_rendered_point_count = 0

func update_height(camera_distance: float, road_surface_height: float = 0.0) -> void:
	_ensure_visuals()
	var close_drive_view := camera_distance < 100.0
	if close_drive_view:
		_set_route_height(road_surface_height + DRIVE_ROUTE_CLEARANCE_M)
		_target_marker.position.y = _route_mesh_instance.position.y + 3.0
		_target_marker.scale = Vector3.ONE * 0.04
		_set_ribbon_width(14.0)
		return
	var spacing := clampf(camera_distance / 6000.0, 4.0, 240.0)
	_set_route_height(road_surface_height + spacing)
	_target_marker.position.y = _route_mesh_instance.position.y + maxf(90.0, spacing)
	_target_marker.scale = Vector3.ONE * clampf(camera_distance / 30000.0, 1.0, 20.0)
	# Keep the route slightly generous through normal map zooms, then continue
	# scaling into the full-country view while capping it to a small fraction of
	# the visible world span instead of letting it become a giant band.
	_set_ribbon_width(clampf(30.0 + camera_distance / 220.0, 34.0, 4200.0))

func _set_route_height(height_m: float) -> void:
	_route_outline_instance.position.y = height_m
	_route_mesh_instance.position.y = height_m

func _set_ribbon_width(wanted_width: float) -> void:
	if is_equal_approx(wanted_width, _ribbon_width_m): return
	_ribbon_width_m = wanted_width
	_rebuild_ribbon()

func route_height() -> float: _ensure_visuals(); return _route_mesh_instance.position.y
func rendered_point_count() -> int: return _rendered_point_count
func ribbon_width_m() -> float: return _ribbon_width_m
func outline_width_m() -> float: return _ribbon_width_m + clampf(_ribbon_width_m * 0.35, 10.0, 900.0)
func target_scale() -> float: _ensure_visuals(); return _target_marker.scale.x

func _route_overlay_material(color: Color, priority: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = priority
	return material

func _ensure_visuals() -> void:
	if _route_mesh_instance != null: return
	_route_outline_instance = MeshInstance3D.new()
	_route_outline_instance.name = "GpsRouteOutline"
	_route_outline_material = _route_overlay_material(Color(0.96, 0.96, 0.94, 1.0), ROUTE_OUTLINE_PRIORITY)
	_route_outline_instance.material_override = _route_outline_material
	add_child(_route_outline_instance)
	_route_mesh_instance = MeshInstance3D.new()
	_route_mesh_instance.name = "GpsRoute"
	_route_material = _route_overlay_material(Color(0.015, 0.015, 0.018, 1.0), ROUTE_CORE_PRIORITY)
	_route_mesh_instance.material_override = _route_material
	add_child(_route_mesh_instance)
	_target_marker = MeshInstance3D.new()
	_target_marker.name = "GpsTarget"
	var sphere := SphereMesh.new()
	sphere.radius = 80.0
	sphere.height = 160.0
	_target_marker.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.35, 0.08)
	_target_marker.material_override = material
	_target_marker.visible = false
	add_child(_target_marker)
