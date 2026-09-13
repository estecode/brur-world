class_name DriveHudAdapter
extends Node

## Adapts public vehicle, routing-world, and navigation outputs into road-vehicle HUD view state.
##
## Dependencies:
## - Reads player vehicle through GpsRouteLayer.get_player_vehicle().
## - Reads explicit OSM road speed limits through RoadSpeedLimitQuery over BRG1/BRS2.
## - Reads remaining route ETA through GpsRouteLayer.current_route_eta_seconds().
## - Pushes only display-ready state into DriveHudPresentation.

const RoadSpeedLimitQueryScript = preload("res://scripts/road_speed_limit_query.gd")
const GRAPH_PATH := "res://world_data/routing.brg"
const SNAP_PATH := "res://world_data/routing_snap.brs"
const SPEED_LIMIT_REFRESH_SECONDS := 0.15

@export var main_path: NodePath
@export var route_layer_path: NodePath
@export var camera_rig_path: NodePath
@export var hud_path: NodePath

var _main: Node
var _route_layer: Node
var _camera_rig: Node
var _hud: CanvasLayer
var _speed_limit_query = RoadSpeedLimitQueryScript.new()
var _speed_limit_refresh_s: float = 0.0
var _last_speed_limit_kmh: Variant = null
var _setup_complete := false

func _ready() -> void:
	if not main_path.is_empty():
		_main = get_node(main_path)
	if not route_layer_path.is_empty():
		_route_layer = get_node(route_layer_path)
	if not camera_rig_path.is_empty():
		_camera_rig = get_node(camera_rig_path)
	if not hud_path.is_empty():
		_hud = get_node(hud_path) as CanvasLayer
	call_deferred("_finish_setup")

func _process(delta: float) -> void:
	if _hud == null or _route_layer == null:
		return
	if not _setup_complete:
		_finish_setup()
	var player: Node3D = _route_layer.call("get_player_vehicle") as Node3D if _route_layer.has_method("get_player_vehicle") else null
	var has_road_vehicle := player != null and player.has_method("speed_kmh")
	_hud.call("set_vehicle_visible", has_road_vehicle)
	if not has_road_vehicle:
		return
	_speed_limit_refresh_s -= maxf(0.0, delta)
	if _speed_limit_refresh_s <= 0.0:
		_last_speed_limit_kmh = _speed_limit_query.speed_limit_kmh_at(player.global_position) if _speed_limit_query.is_ready() else null
		_speed_limit_refresh_s = SPEED_LIMIT_REFRESH_SECONDS
	var eta_seconds: Variant = null
	if _route_layer.has_method("current_route_eta_seconds"):
		var eta := float(_route_layer.call("current_route_eta_seconds"))
		if is_finite(eta) and eta >= 0.0:
			eta_seconds = eta
	_hud.call("set_state", {
		"current_speed_kmh": float(player.call("speed_kmh")),
		"speed_limit_kmh": _last_speed_limit_kmh,
		"eta_seconds": eta_seconds,
	})

func _finish_setup() -> void:
	if _setup_complete or _main == null:
		return
	if not _main.has_method("get_world_coordinates"):
		return
	var world_coordinates = _main.call("get_world_coordinates")
	if world_coordinates == null:
		return
	_speed_limit_query.setup(GRAPH_PATH, SNAP_PATH, world_coordinates)
	_setup_complete = true
