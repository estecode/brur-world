extends Node

## Rebases Drive presentation close to the followed vehicle without changing logical world coordinates.
##
## Dependencies:
## - CameraRig owns the presentation-only Drive render origin API.
## - World, POI, cloud and building roots are presentation nodes wired explicitly by the scene.
## - GpsRouteLayer exposes the authoritative player vehicle; Vehicle owns its own VisualRoot adapter.
## - Transparent World background meshes are localized before GPU upload so Sweden-scale vertices never rely on large-minus-large render transforms in Drive.

@export var camera_rig_path: NodePath
@export var world_path: NodePath
@export var poi_layer_path: NodePath
@export var cloud_field_path: NodePath
@export var building_layer_path: NodePath
@export var gps_route_layer_path: NodePath

const LOGICAL_XZ_META: StringName = &"brur_drive_logical_xz"
const LOGICAL_MESH_META: StringName = &"brur_drive_logical_mesh"
const LOCALIZED_ORIGIN_META: StringName = &"brur_drive_localized_origin"
const DRIVE_GROUND_DIAMETER_MIN_M: float = 4096.0
const DRIVE_GROUND_DIAMETER_MAX_M: float = 12000.0

var _camera_rig: Node = null
var _world: Node3D = null
var _poi_layer: Node3D = null
var _cloud_field: Node3D = null
var _building_layer: Node3D = null
var _gps_route_layer: Node = null

func _ready() -> void:
	_camera_rig = get_node_or_null(camera_rig_path)
	_world = get_node_or_null(world_path) as Node3D
	_poi_layer = get_node_or_null(poi_layer_path) as Node3D
	_cloud_field = get_node_or_null(cloud_field_path) as Node3D
	_building_layer = get_node_or_null(building_layer_path) as Node3D
	_gps_route_layer = get_node_or_null(gps_route_layer_path)
	if _camera_rig == null or _world == null or _building_layer == null or _gps_route_layer == null:
		push_error("Drive render-origin composition is missing a required scene dependency")
		set_process(false)
		return
	if not _camera_rig.has_method("get_render_origin_world") or not _gps_route_layer.has_method("get_player_vehicle"):
		push_error("Drive render-origin composition dependencies do not expose required APIs")
		set_process(false)
		return
	_sync_render_origin()

func _process(_delta: float) -> void:
	_sync_render_origin()

func _sync_render_origin() -> void:
	if _camera_rig == null:
		return
	var origin: Vector3 = _camera_rig.call("get_render_origin_world")
	# Road/building transforms and background mesh vertices must all be local.
	# Merely putting a huge inverse offset on a parent keeps precision loss in the
	# GPU transform path. Transparent BRM2/ocean geometry is therefore rebuilt
	# from its canonical mesh into the current render cell when that cell changes.
	_set_horizontal_offset(_world, Vector3.ZERO)
	_rebase_world_children(_world, origin)
	_set_horizontal_offset(_building_layer, Vector3.ZERO)
	_rebase_building_meshes(_building_layer, origin)

	var offset := Vector3(-origin.x, 0.0, -origin.z)
	_set_horizontal_offset(_poi_layer, offset)
	_set_horizontal_offset(_cloud_field, offset)
	var player: Node = _gps_route_layer.call("get_player_vehicle")
	if player != null and player.has_method("set_render_origin_world"):
		player.call("set_render_origin_world", origin)
	if _gps_route_layer.has_method("set_render_origin_world"):
		_gps_route_layer.call("set_render_origin_world", origin)

func _rebase_world_children(root: Node3D, origin: Vector3) -> void:
	if root == null:
		return
	for child_value in root.get_children():
		var child := child_value as Node3D
		if child == null:
			continue
		if _is_decorative_background(child):
			_rebase_background_mesh(child as MeshInstance3D, origin)
		else:
			_rebase_node(child, origin)

func _is_decorative_background(node: Node3D) -> bool:
	if not node is MeshInstance3D:
		return false
	var instance := node as MeshInstance3D
	var material := instance.material_override as StandardMaterial3D
	return material != null and material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED

func _rebase_background_mesh(instance: MeshInstance3D, origin: Vector3) -> void:
	if instance == null or instance.mesh == null:
		return
	if not instance.has_meta(LOGICAL_MESH_META):
		instance.set_meta(LOGICAL_MESH_META, instance.mesh)
	if not instance.has_meta(LOGICAL_XZ_META):
		instance.set_meta(LOGICAL_XZ_META, Vector2(instance.position.x, instance.position.z))
	var logical_mesh := instance.get_meta(LOGICAL_MESH_META) as Mesh
	var logical_xz: Vector2 = instance.get_meta(LOGICAL_XZ_META)
	if origin.is_zero_approx():
		instance.mesh = logical_mesh
		instance.position.x = logical_xz.x
		instance.position.z = logical_xz.y
		instance.remove_meta(LOCALIZED_ORIGIN_META)
		return

	# The ocean base is a Sweden-scale PlaneMesh. In Drive only a bounded local
	# patch around the camera is required, so never send the country-scale plane
	# vertices through the Drive render path.
	if logical_mesh is PlaneMesh:
		var local_plane := PlaneMesh.new()
		var far_m := 5000.0
		if _camera_rig != null:
			far_m = float(_camera_rig.get("drive_far_m"))
		var diameter := clampf(far_m * 2.2, DRIVE_GROUND_DIAMETER_MIN_M, DRIVE_GROUND_DIAMETER_MAX_M)
		local_plane.size = Vector2(diameter, diameter)
		instance.mesh = local_plane
		instance.position.x = 0.0
		instance.position.z = 0.0
		instance.set_meta(LOCALIZED_ORIGIN_META, Vector2(origin.x, origin.z))
		return

	var previous_origin := Vector2(INF, INF)
	if instance.has_meta(LOCALIZED_ORIGIN_META):
		previous_origin = instance.get_meta(LOCALIZED_ORIGIN_META)
	var next_origin := Vector2(origin.x, origin.z)
	if previous_origin == next_origin:
		return
	var localized := _localized_mesh(logical_mesh, logical_xz, next_origin)
	if localized != null:
		instance.mesh = localized
		instance.position.x = 0.0
		instance.position.z = 0.0
		instance.set_meta(LOCALIZED_ORIGIN_META, next_origin)

func _localized_mesh(source: Mesh, logical_xz: Vector2, render_origin: Vector2) -> ArrayMesh:
	if not source is ArrayMesh:
		return null
	var source_array := source as ArrayMesh
	var result := ArrayMesh.new()
	for surface_index in range(source_array.get_surface_count()):
		var arrays: Array = source_array.surface_get_arrays(surface_index)
		if arrays.size() <= Mesh.ARRAY_VERTEX:
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex_index in range(vertices.size()):
			var vertex := vertices[vertex_index]
			vertex.x += logical_xz.x - render_origin.x
			vertex.z += logical_xz.y - render_origin.y
			vertices[vertex_index] = vertex
		arrays[Mesh.ARRAY_VERTEX] = vertices
		result.add_surface_from_arrays(source_array.surface_get_primitive_type(surface_index), arrays)
		var surface_material := source_array.surface_get_material(surface_index)
		if surface_material != null:
			result.surface_set_material(result.get_surface_count() - 1, surface_material)
	return result

func _rebase_building_meshes(root: Node3D, origin: Vector3) -> void:
	if root == null:
		return
	for child_value in root.get_children():
		var child := child_value as Node3D
		if child == null:
			continue
		_rebase_building_branch(child, origin)

func _rebase_building_branch(node: Node3D, origin: Vector3) -> void:
	if node is MeshInstance3D:
		_rebase_node(node, origin)
		return
	for child_value in node.get_children():
		var child := child_value as Node3D
		if child != null:
			_rebase_building_branch(child, origin)

func _rebase_node(node: Node3D, origin: Vector3) -> void:
	if origin.is_zero_approx():
		if node.has_meta(LOGICAL_XZ_META):
			var logical: Vector2 = node.get_meta(LOGICAL_XZ_META)
			node.position.x = logical.x
			node.position.z = logical.y
			node.remove_meta(LOGICAL_XZ_META)
		return
	if not node.has_meta(LOGICAL_XZ_META):
		node.set_meta(LOGICAL_XZ_META, Vector2(node.position.x, node.position.z))
	var logical: Vector2 = node.get_meta(LOGICAL_XZ_META)
	node.position.x = logical.x - origin.x
	node.position.z = logical.y - origin.z

func _set_horizontal_offset(node: Node3D, offset: Vector3) -> void:
	if node == null:
		return
	node.position.x = offset.x
	node.position.z = offset.z
