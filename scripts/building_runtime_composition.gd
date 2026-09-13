extends Node

## Wires the production building stream to the normal game without owning building policy or data.
##
## Dependencies:
## - Main supplies the shared projected-world origin and current rendered road-surface height.
## - CameraRig supplies focus and altitude.
## - BuildingStreamLayer owns building streaming/rendering behavior.

const WorldCoordinatesScript = preload("res://scripts/world_coordinates.gd")

@export var main_path: NodePath
@export var camera_rig_path: NodePath
@export var building_layer_path: NodePath
@export var tile_data_dir: String = "res://world_data/building_tiles"
@export var building_tile_size_m: float = 2000.0

var _main: Node = null
var _building_layer: Node3D = null

func _ready() -> void:
	call_deferred("_compose")

func _process(_delta: float) -> void:
	_sync_surface_height()

func _compose() -> void:
	var main: Node = get_node_or_null(main_path)
	var camera_rig: Node = get_node_or_null(camera_rig_path)
	var building_layer: Node = get_node_or_null(building_layer_path)
	if main == null or camera_rig == null or building_layer == null:
		push_error("Building runtime composition is missing a required scene dependency")
		return
	if not main.has_method("get_world_coordinates") or not main.has_method("get_road_surface_height") or not building_layer.has_method("setup"):
		push_error("Building runtime composition dependencies do not expose required APIs")
		return
	if not building_layer is Node3D:
		push_error("Building runtime composition requires a Node3D building layer")
		return
	_main = main
	_building_layer = building_layer as Node3D
	_sync_surface_height()
	var world_coordinates = main.call("get_world_coordinates")
	var building_coordinates = WorldCoordinatesScript.new(world_coordinates.origin, building_tile_size_m)
	building_layer.call("setup", building_coordinates, camera_rig, tile_data_dir)

func _sync_surface_height() -> void:
	if _main == null or _building_layer == null or not _main.has_method("get_road_surface_height"):
		return
	# Building meshes are tile-local from y=0. Keep their internal base neutral and
	# move the layer as one presentation object so already-active meshes follow
	# map/drive depth-layout changes without a reload.
	if not is_zero_approx(float(_building_layer.get("base_height_m"))):
		_building_layer.set("base_height_m", 0.0)
	_building_layer.position.y = float(_main.call("get_road_surface_height"))
