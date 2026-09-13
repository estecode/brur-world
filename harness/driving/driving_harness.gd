extends Node3D

## Composes one production player vehicle for manual and AI/GPS driving-policy playtests.
##
## Dependencies:
## - Uses the production player_vehicle scene, VehicleRouteFollower, RouteDrivingPolicy and CameraRig implementation.
## - Fixture roads/speed limits/intersection observations are deterministic harness inputs, not alternate vehicle/routing logic.

const PlayerVehicleScene = preload("res://scenes/player_vehicle.tscn")
const RouteDrivingPolicyScript = preload("res://scripts/route_driving_policy.gd")
const ROAD_WIDTH: float = 10.0
const ROAD_HEIGHT: float = 0.18
const ROAD_Y: float = 0.10
const GRID_MIN_X: float = -90.0
const GRID_MAX_X: float = 90.0
const GRID_MIN_Z: float = -65.0
const GRID_MAX_Z: float = 65.0
const INNER_X_LEFT: float = -30.0
const INNER_X_RIGHT: float = 30.0
const INNER_Z_NEAR: float = -22.0
const INNER_Z_FAR: float = 22.0
const RESET_CAMERA_ALTITUDE_M: float = 115.0
const ROUTE_SPEED_LIMIT_MPS: float = 13.9
const INTERSECTION_ROUTE_INDEX: int = 3
const INTERSECTION_SAFE_SPEED_MPS: float = 8.0
const INTERSECTION_BASE_SAFE_GAP_S: float = 4.0

enum ControlMode {
	MANUAL,
	GPS,
}

enum GapScenario {
	CLEAR,
	ASSERTIVE,
	RISKY,
}

@onready var camera_rig: Node3D = $CameraRig
@onready var control_mode: OptionButton = $Ui/Panel/Margin/VBox/ControlMode
@onready var set_route_button: Button = $Ui/Panel/Margin/VBox/SetRoute
@onready var clear_route_button: Button = $Ui/Panel/Margin/VBox/ClearRoute
@onready var follow_car: CheckButton = $Ui/Panel/Margin/VBox/FollowCar
@onready var driving_mode: OptionButton = $Ui/Panel/Margin/VBox/DrivingMode
@onready var intersection_gap: OptionButton = $Ui/Panel/Margin/VBox/IntersectionGap
@onready var status: Label = $Ui/Panel/Margin/VBox/Status
@onready var speed: Label = $Ui/Panel/Margin/VBox/Speed

var player: Node3D = null
var player_controller: Node = null
var route_follower: Node = null
var _fixture_route: PackedVector3Array = PackedVector3Array()
var _fixture_speed_limits: PackedFloat32Array = PackedFloat32Array()
var _control_mode: int = ControlMode.MANUAL
var _gap_scenario: int = GapScenario.CLEAR
var _route_is_set: bool = false

func _ready() -> void:
	_build_ground()
	_build_connected_roads()
	_spawn_player()
	_fixture_route = _build_fixture_route()
	_fixture_speed_limits = _build_fixture_speed_limits(_fixture_route.size())
	_setup_control_modes()
	_setup_driving_modes()
	_setup_intersection_scenarios()
	control_mode.item_selected.connect(_on_control_mode_selected)
	set_route_button.pressed.connect(_on_set_route_pressed)
	clear_route_button.pressed.connect(_on_clear_route_pressed)
	follow_car.toggled.connect(_on_follow_car_toggled)
	driving_mode.item_selected.connect(_on_driving_mode_selected)
	intersection_gap.item_selected.connect(_on_intersection_gap_selected)
	$Ui/Panel/Margin/VBox/Reset.pressed.connect(_reset_player)
	follow_car.button_pressed = true
	_reset_player()
	_set_control_mode(ControlMode.MANUAL)

func _process(_delta: float) -> void:
	if player == null:
		return
	speed.text = "Speed: %.1f km/h   Road limit: %.0f km/h" % [float(player.call("speed_kmh")), ROUTE_SPEED_LIMIT_MPS * 3.6]
	var owner: int = int(player.call("control_owner"))
	status.text = "Control: %s   Route: %s   AI: %s   Intersection: %s   Camera: %s" % [
		"GPS" if owner == 1 else "MANUAL",
		"SET" if _route_is_set else "NONE",
		_active_mode_name() if _control_mode == ControlMode.GPS and _route_is_set else "inactive",
		_gap_scenario_name(),
		"FOLLOW" if follow_car.button_pressed else "FREE",
	]

func _spawn_player() -> void:
	player = PlayerVehicleScene.instantiate() as Node3D
	player.name = "PlayerVehicle"
	add_child(player)
	player_controller = player.get_node_or_null("PlayerVehicleController")
	route_follower = player.get_node_or_null("VehicleRouteFollower")

func _setup_control_modes() -> void:
	control_mode.clear()
	control_mode.add_item("Manual Drive", ControlMode.MANUAL)
	control_mode.add_item("GPS Drive", ControlMode.GPS)
	control_mode.select(0)

func _setup_driving_modes() -> void:
	driving_mode.clear()
	driving_mode.add_item("Normal", RouteDrivingPolicyScript.Mode.NORMAL)
	driving_mode.add_item("Aggressive", RouteDrivingPolicyScript.Mode.AGGRESSIVE)
	driving_mode.add_item("Maniac", RouteDrivingPolicyScript.Mode.MANIAC)
	if route_follower == null:
		driving_mode.disabled = true
		return
	var active_mode: int = int(route_follower.call("driving_mode"))
	for index in driving_mode.item_count:
		if driving_mode.get_item_id(index) == active_mode:
			driving_mode.select(index)
			return

func _setup_intersection_scenarios() -> void:
	intersection_gap.clear()
	intersection_gap.add_item("Clear gap (8.0 s)", GapScenario.CLEAR)
	intersection_gap.add_item("Assertive gap (3.0 s)", GapScenario.ASSERTIVE)
	intersection_gap.add_item("Risky gap (2.0 s)", GapScenario.RISKY)
	intersection_gap.select(0)

func _on_control_mode_selected(index: int) -> void:
	_set_control_mode(control_mode.get_item_id(index))

func _set_control_mode(next_mode: int) -> void:
	_control_mode = next_mode
	var gps_requested := _control_mode == ControlMode.GPS
	if player_controller != null:
		player_controller.set("enabled", not gps_requested)
	if route_follower != null:
		var gps_enabled := gps_requested and _route_is_set
		route_follower.call("set_follow_enabled", gps_enabled)
		if gps_requested and not _route_is_set:
			player.call("set_control_owner", 0)
	driving_mode.disabled = not gps_requested or not _route_is_set or route_follower == null
	# Manual drive reserves WASD for the player; GPS drive leaves WASD available for map pan.
	camera_rig.call("set_drive_mode", not gps_requested)
	if follow_car.button_pressed:
		camera_rig.call("set_follow_target", player)
		if gps_requested:
			camera_rig.call("set_map_follow_enabled", true)

func _on_set_route_pressed() -> void:
	_set_fixture_route_and_start()

func _set_fixture_route_and_start() -> void:
	if route_follower == null:
		return
	route_follower.call("set_follow_enabled", false)
	route_follower.call("set_route", _fixture_route, _fixture_speed_limits)
	_route_is_set = true
	_apply_intersection_scenario()
	control_mode.select(ControlMode.GPS)
	_set_control_mode(ControlMode.GPS)

func _on_clear_route_pressed() -> void:
	if route_follower != null:
		route_follower.call("set_follow_enabled", false)
		route_follower.call("clear_route")
	_route_is_set = false
	control_mode.select(ControlMode.MANUAL)
	_set_control_mode(ControlMode.MANUAL)

func _on_driving_mode_selected(index: int) -> void:
	if route_follower == null or _control_mode != ControlMode.GPS or not _route_is_set:
		return
	var requested_mode: int = driving_mode.get_item_id(index)
	if not bool(route_follower.call("set_driving_mode", requested_mode)):
		_setup_driving_modes()

func _on_intersection_gap_selected(index: int) -> void:
	_gap_scenario = intersection_gap.get_item_id(index)
	_apply_intersection_scenario()

func _apply_intersection_scenario() -> void:
	if route_follower == null or not _route_is_set:
		return
	route_follower.call(
		"set_upcoming_intersection",
		INTERSECTION_ROUTE_INDEX,
		INTERSECTION_SAFE_SPEED_MPS,
		INTERSECTION_BASE_SAFE_GAP_S,
		_observed_gap_seconds()
	)

func _observed_gap_seconds() -> float:
	match _gap_scenario:
		GapScenario.ASSERTIVE:
			return 3.0
		GapScenario.RISKY:
			return 2.0
		_:
			return 8.0

func _gap_scenario_name() -> String:
	match _gap_scenario:
		GapScenario.ASSERTIVE:
			return "3.0 s gap"
		GapScenario.RISKY:
			return "2.0 s gap"
		_:
			return "8.0 s gap"

func _active_mode_name() -> String:
	if route_follower == null:
		return "Unavailable"
	match int(route_follower.call("driving_mode")):
		RouteDrivingPolicyScript.Mode.NORMAL:
			return "Normal"
		RouteDrivingPolicyScript.Mode.AGGRESSIVE:
			return "Aggressive"
		RouteDrivingPolicyScript.Mode.MANIAC:
			return "Maniac"
		_:
			return "Unknown"

func _reset_player() -> void:
	if player == null:
		return
	if route_follower != null:
		route_follower.call("set_follow_enabled", false)
	player.call("set_world_position", Vector3(GRID_MIN_X, 0.8, GRID_MAX_Z))
	# The fixture route initially travels east (+X); heading -PI/2 faces +X in the shared vehicle convention.
	player.call("set_motion_state", 0.0, -PI / 2.0)
	if _route_is_set and route_follower != null:
		route_follower.call("set_route", _fixture_route, _fixture_speed_limits)
		_apply_intersection_scenario()
	if follow_car.button_pressed:
		camera_rig.call("set_follow_target", player)
		camera_rig.call("set_view_altitude", player.global_position, RESET_CAMERA_ALTITUDE_M)
	_set_control_mode(_control_mode)

func _on_follow_car_toggled(enabled: bool) -> void:
	if player == null:
		return
	if enabled:
		camera_rig.call("set_follow_target", player)
		if _control_mode == ControlMode.GPS:
			camera_rig.call("set_map_follow_enabled", true)
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
	for x in [INNER_X_LEFT, INNER_X_RIGHT]:
		_add_road(Vector3(x, ROAD_Y, 0.0), Vector3(ROAD_WIDTH, ROAD_HEIGHT, GRID_MAX_Z - GRID_MIN_Z + ROAD_WIDTH))
	for z in [INNER_Z_NEAR, INNER_Z_FAR]:
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
		Vector3(INNER_X_LEFT, 0.8, GRID_MAX_Z),
		Vector3(INNER_X_RIGHT, 0.8, GRID_MAX_Z),
		Vector3(GRID_MAX_X, 0.8, GRID_MAX_Z),
		Vector3(GRID_MAX_X, 0.8, INNER_Z_FAR),
		Vector3(GRID_MAX_X, 0.8, INNER_Z_NEAR),
		Vector3(GRID_MAX_X, 0.8, GRID_MIN_Z),
		Vector3(INNER_X_RIGHT, 0.8, GRID_MIN_Z),
		Vector3(INNER_X_LEFT, 0.8, GRID_MIN_Z),
		Vector3(GRID_MIN_X, 0.8, GRID_MIN_Z),
		Vector3(GRID_MIN_X, 0.8, INNER_Z_NEAR),
		Vector3(GRID_MIN_X, 0.8, INNER_Z_FAR),
	])

func _build_fixture_speed_limits(count: int) -> PackedFloat32Array:
	var limits := PackedFloat32Array()
	limits.resize(count)
	for index in range(count):
		limits[index] = ROUTE_SPEED_LIMIT_MPS
	return limits
