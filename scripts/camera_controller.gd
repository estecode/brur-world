extends Node3D

# Minimal perspective map camera: WASD/arrow pan, mouse-wheel zoom, middle/right-drag pan.

@export var min_distance := 1500.0
@export var max_distance := 800000.0
@export var start_distance := 120000.0
@export var pitch_degrees := 55.0
@export var move_speed_factor := 0.8

var focus := Vector3.ZERO
var distance := start_distance
var dragging := false
var last_mouse := Vector2.ZERO

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	_apply_camera()

func _process(delta: float) -> void:
	var input := Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	)
	if Input.is_key_pressed(KEY_A): input.x -= 1.0
	if Input.is_key_pressed(KEY_D): input.x += 1.0
	if Input.is_key_pressed(KEY_W): input.y -= 1.0
	if Input.is_key_pressed(KEY_S): input.y += 1.0
	if input.length_squared() > 0.0:
		input = input.normalized()
		var speed := max(250.0, distance * move_speed_factor)
		focus += Vector3(input.x, 0.0, input.y) * speed * delta
		_apply_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			distance = max(min_distance, distance * 0.78)
			_apply_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			distance = min(max_distance, distance / 0.78)
			_apply_camera()
		elif event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			dragging = event.pressed
			last_mouse = event.position
	elif event is InputEventMouseMotion and dragging:
		var delta_px := event.position - last_mouse
		last_mouse = event.position
		var meters_per_px := distance / 900.0
		focus += Vector3(-delta_px.x, 0.0, -delta_px.y) * meters_per_px
		_apply_camera()

func _apply_camera() -> void:
	position = focus
	var pitch := deg_to_rad(pitch_degrees)
	camera.position = Vector3(0.0, sin(pitch) * distance, cos(pitch) * distance)
	camera.look_at(focus, Vector3.UP)

func get_focus_world() -> Vector3:
	return focus

func get_distance() -> float:
	return distance
