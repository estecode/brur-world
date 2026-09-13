extends Node

## Rebases Drive presentation close to the followed vehicle without changing logical world coordinates.
##
## Dependencies:
## - CameraRig owns the presentation-only Drive render origin API.
## - World, POI, cloud and building roots are presentation nodes wired explicitly by the scene.
## - GpsRouteLayer exposes the authoritative player vehicle; Vehicle owns its own VisualRoot adapter.

@export var camera_rig_path: NodePath
@export var world_path: NodePath
@export var poi_layer_path: NodePath
@export var cloud_field_path: NodePath
@export var building_layer_path: NodePath
@export var gps_route_layer_path: NodePath

const LOGICAL_XZ_META: StringName = &"brur_drive_logical_xz"

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
	# Do not keep a huge inverse offset on the World/BuildingLayer parent while
	# their children retain huge logical coordinates. That still performs a
	# large-minus-large transform before rendering and loses near-ground precision.
	# Instead keep those roots neutral and rebase the actual GPU-facing children.
	_set_horizontal_offset(_world, Vector3.ZERO)
	_rebase_direct_children(_world, origin)
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

func _rebase_direct_children(root: Node3D, origin: Vector3) -> void:
	if root == null:
		return
	for child_value in root.get_children():
		var child := child_value as Node3D
		if child == null:
			continue
		_rebase_node(child, origin)

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
