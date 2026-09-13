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
	var offset := Vector3(-origin.x, 0.0, -origin.z)
	_set_horizontal_offset(_world, offset)
	_set_horizontal_offset(_poi_layer, offset)
	_set_horizontal_offset(_cloud_field, offset)
	_set_horizontal_offset(_building_layer, offset)
	var player: Node = _gps_route_layer.call("get_player_vehicle")
	if player != null and player.has_method("set_render_origin_world"):
		player.call("set_render_origin_world", origin)
	if _gps_route_layer.has_method("set_render_origin_world"):
		_gps_route_layer.call("set_render_origin_world", origin)

func _set_horizontal_offset(node: Node3D, offset: Vector3) -> void:
	if node == null:
		return
	node.position.x = offset.x
	node.position.z = offset.z
