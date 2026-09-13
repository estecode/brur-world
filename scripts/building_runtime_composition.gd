extends Node

## Wires the production building stream to the normal game without owning building policy or data.
##
## Dependencies:
## - Main supplies the shared projected-world origin through WorldCoordinates.
## - CameraRig supplies focus, altitude, and ground-view corners.
## - BuildingStreamLayer consumes the derived prebuilt building mesh LOD directory.

const WorldCoordinatesScript = preload("res://scripts/world_coordinates.gd")

@export var main_path: NodePath
@export var camera_rig_path: NodePath
@export var building_layer_path: NodePath
@export var tile_data_dir: String = "res://world_data/building_mesh_lod"
@export var building_tile_size_m: float = 2000.0

func _ready() -> void:
	call_deferred("_compose")

func _compose() -> void:
	var main: Node = get_node_or_null(main_path)
	var camera_rig: Node = get_node_or_null(camera_rig_path)
	var building_layer: Node = get_node_or_null(building_layer_path)
	if main == null or camera_rig == null or building_layer == null:
		push_error("Building runtime composition is missing a required scene dependency")
		return
	if not main.has_method("get_world_coordinates") or not building_layer.has_method("setup"):
		push_error("Building runtime composition dependencies do not expose required APIs")
		return
	var world_coordinates = main.call("get_world_coordinates")
	var building_coordinates = WorldCoordinatesScript.new(world_coordinates.origin, building_tile_size_m)
	building_layer.call("setup", building_coordinates, camera_rig, tile_data_dir)
