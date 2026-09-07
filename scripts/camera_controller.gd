extends Node3D

# Minimal perspective map camera: WASD/arrow pan, mouse-wheel zoom, middle/right-drag pan.

@export var min_distance: float = 1500.0
@export var max_distance: float = 1400000.0
@export var start_distance: float = 800000.0
@export var pitch_degrees: float = 55.0
@export var move_speed_factor: float = 0.8

var focus: Vector3 = Vector3.ZERO
var distance: float = 800000.0
var dragging: bool = false
var last_mouse: Vector2 = Vector2.ZERO

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	distance = start_distance
	_apply_camera()

func _process(delta: float) -> void:
	var input: Vector2 = Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	)
	if Input.is_key_pressed(KEY_A):
		input.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input.x += 1.0
	if Input.is_key_pressed(KEY_W):
		input.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		input.y += 1.0
	if input.length_squared() > 0.0:
		input = input.normalized()
		var speed: float = maxf(250.0, distance * move_speed_factor)
		focus += Vector3(input.x, 0.0, input.y) * speed * delta
		_apply_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button_event.pressed:
			distance = maxf(min_distance, distance * 0.78)
			_apply_camera()
		elif mouse_button_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button_event.pressed:
			distance = minf(max_distance, distance / 0.78)
			_apply_camera()
		elif mouse_button_event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			dragging = mouse_button_event.pressed
			last_mouse = mouse_button_event.position
	elif event is InputEventMouseMotion and dragging:
		var mouse_motion_event: InputEventMouseMotion = event as InputEventMouseMotion
		var delta_px: Vector2 = mouse_motion_event.position - last_mouse
		last_mouse = mouse_motion_event.position
		var meters_per_px: float = distance / 900.0
		focus += Vector3(-delta_px.x, 0.0, -delta_px.y) * meters_per_px
		_apply_camera()

func _apply_camera() -> void:
	position = focus
	var pitch: float = deg_to_rad(pitch_degrees)
	camera.position = Vector3(0.0, sin(pitch) * distance, cos(pitch) * distance)
	camera.look_at(global_position, Vector3.UP)

func get_focus_world() -> Vector3:
	return focus

func get_distance() -> float:
	return distance
