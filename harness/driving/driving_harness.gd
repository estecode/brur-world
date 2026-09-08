extends Node3D

## Composes a tiny connected road-grid fixture around the production player vehicle for driving playtests.
##
## Dependencies:
## - Uses the production player_vehicle scene, VehicleRouteFollower and CameraRig implementation.
## - Fixture roads are presentation-only meter-scale guides; they do not duplicate routing or vehicle dynamics.

const PlayerVehicleScene = preload("res://scenes/player_vehicle.tscn")
const ROAD_WIDTH: float = 10.0
const ROAD_HEIGHT: float = 0.18
const ROAD_Y: float = 0.10
const GRID_MIN_X: float = -90.0
const GRID_MAX_X: float = 90.0
const GRID_MIN_Z: float = -65.0
const GRID_MAX_Z: float = 65.0
const INNER_X: PackedFloat32Array = PackedFloat32Array([-30.0, 30.0])
const INNER_Z: PackedFloat32Array = PackedFloat32Array([-22.0, 22.0])

@onready var camera_rig: Node3D = $CameraRig
@onready var follow_route: CheckButton = $Ui/Panel/Margin/VBox/FollowRoute
@onready var follow_car: CheckButton = $Ui/Panel/Margin/VBox/FollowCar
@onready var status: Label = $Ui/Panel/Margin/VBox/Status
@onready var speed: Label = $Ui/Panel/Margin/VBox/Speed

var player: Node3D = null
var player_controller: Node = null
var route_follower: Node = null
var _fixture_route: PackedVector3Array = PackedVector3Array()

func _ready() -> void:
	_build_ground()
	_build_connected_roads()
	_spawn_player()
	_fixture_route = _build_fixture_route()
	if route_follower != null:
		route_follower.call("set_route", _fixture_route)
	follow_route.toggled.connect(_on_follow_route_toggled)
	follow_car.toggled.connect(_on_follow_car_toggled)
	$Ui/Panel/Margin/VBox/Reset.pressed.connect(_reset_player)
	follow_car.button_pressed = true
	_on_follow_car_toggled(true)
	_reset_player()

func _process(_delta: float) -> void:
	if player == null:
		return
	speed.text = "Speed: %.1f km/h" % float(player.call("speed_kmh"))
	var owner: int = int(player.call("control_owner"))
	status.text = "Control: %s   Route: %s   Camera: %s" % [
		"GPS" if owner == 1 else "MANUAL",
		"FOLLOW" if follow_route.button_pressed else "VISIBLE / MANUAL",
		"FOLLOW" if follow_car.button_pressed else "FREE",
	]

func _spawn_player() -> void:
	player = PlayerVehicleScene.instantiate() as Node3D
	player.name = "PlayerVehicle"
	add_child(player)
	player_controller = player.get_node_or_null("PlayerVehicleController")
	route_follower = player.get_node_or_null("VehicleRouteFollower")
	if player_controller != null:
		player_controller.connect("manual_input_detected", _on_manual_input_detected)

func _reset_player() -> void:
	if player == null:
		return
	if route_follower != null:
		route_follower.call("set_follow_enabled", false)
		route_follower.call("set_route", _fixture_route)
	follow_route.set_pressed_no_signal(false)
	player.call("set_world_position", Vector3(GRID_MIN_X, 0.8, GRID_MAX_Z))
	player.call("set_motion_state", 0.0, PI / 2.0)
	if follow_car.button_pressed:
		camera_rig.call("set_follow_target", player)
		camera_rig.call("set_view", player.global_position, 115.0)

func _on_follow_route_toggled(enabled: bool) -> void:
	if route_follower == null:
		follow_route.set_pressed_no_signal(false)
		return
	if not bool(route_follower.call("set_follow_enabled", enabled)):
		follow_route.set_pressed_no_signal(false)

func _on_manual_input_detected() -> void:
	if not follow_route.button_pressed:
		return
	follow_route.set_pressed_no_signal(false)
	if route_follower != null:
		route_follower.call("set_follow_enabled", false)

func _on_follow_car_toggled(enabled: bool) -> void:
	if player == null:
		return
	if enabled:
		camera_rig.call("set_follow_target", player)
		camera_rig.call("set_view", player.global_position, camera_rig.call("get_distance"))
	else:
		camera_rig.call("clear_follow_target")

func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(250.0, 0.2, 200.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.20, 0.34, 0.19)
	mesh.material = material
	ground.mesh = mesh
	ground.position.y = -0.12
	add_child(ground)

func _build_connected_roads() -> void:
	_add_road(Vector3((GRID_MIN_X + GRID_MAX_X) * 0.5, ROAD_Y, GRID_MIN_Z), Vector3(GRID_MAX_X - GRID_MIN_X + ROAD_WIDTH, ROAD_HEIGHT, ROAD_WIDTH))
	_add_road(Vector3((GRID_MIN_X + GRID_MAX_X) * 0.5, ROAD_Y, GRID_MAX_Z), Vector3(GRID_MAX_X - GRID_MIN_X + ROAD_WIDTH, ROAD_HEIGHT, ROAD_WIDTH))
	_add_road(Vector3(GRID_MIN_X, ROAD_Y, (GRID_MIN_Z + GRID_MAX_Z) * 0.5), Vector3(ROAD_WIDTH, ROAD_HEIGHT, GRID_MAX_Z - GRID_MIN_Z + ROAD_WIDTH))
	_add_road(Vector3(GRID_MAX_X, ROAD_Y, (GRID_MIN_Z + GRID_MAX_Z) * 0.5), Vector3(ROAD_WIDTH, ROAD_HEIGHT, GRID_MAX_Z - GRID_MIN_Z + ROAD_WIDTH))
	for x in INNER_X:
		_add_road(Vector3(x, ROAD_Y, 0.0), Vector3(ROAD_WIDTH, ROAD_HEIGHT, GRID_MAX_Z - GRID_MIN_Z + ROAD_WIDTH))
	for z in INNER_Z:
		_add_road(Vector3(0.0, ROAD_Y, z), Vector3(GRID_MAX_X - GRID_MIN_X + ROAD_WIDTH, ROAD_HEIGHT, ROAD_WIDTH))

func _add_road(position_value: Vector3, size_value: Vector3) -> void:
	var road := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size_value
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.18, 0.19, 0.20)
	mesh.material = material
	road.mesh = mesh
	road.position = position_value
	$Roads.add_child(road)

func _build_fixture_route() -> PackedVector3Array:
	return PackedVector3Array([
		Vector3(GRID_MIN_X, 0.8, GRID_MAX_Z),
		Vector3(-30.0, 0.8, GRID_MAX_Z),
		Vector3(30.0, 0.8, GRID_MAX_Z),
		Vector3(GRID_MAX_X, 0.8, GRID_MAX_Z),
		Vector3(GRID_MAX_X, 0.8, 22.0),
		Vector3(GRID_MAX_X, 0.8, -22.0),
		Vector3(GRID_MAX_X, 0.8, GRID_MIN_Z),
		Vector3(30.0, 0.8, GRID_MIN_Z),
		Vector3(-30.0, 0.8, GRID_MIN_Z),
		Vector3(GRID_MIN_X, 0.8, GRID_MIN_Z),
		Vector3(GRID_MIN_X, 0.8, -22.0),
		Vector3(GRID_MIN_X, 0.8, 22.0),
		Vector3(GRID_MIN_X, 0.8, GRID_MAX_Z),
	])
