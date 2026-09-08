extends Node3D

## Controls the continuous map-to-gameplay camera and exposes its view state.
##
## Dependencies:
## - Owns Camera3D framing/input only.
## - Emits focus, distance, and camera-position changes for explicitly wired presentation consumers.

signal view_changed(focus_world: Vector3, distance_m: float, camera_world_position: Vector3)

@export var min_distance: float = 1500.0
@export var max_distance: float = 1400000.0
@export var start_distance: float = 800000.0
@export var move_speed_factor: float = 0.8

# Zoomed-out Sweden overview.
@export var overview_pitch_degrees: float = 72.0
@export var overview_fov: float = 40.0

# Zoomed-in gameplay/drone framing.
@export var gameplay_pitch_degrees: float = 45.0
@export var gameplay_fov: float = 52.0
@export var gameplay_forward_look: float = 0.42

# Camera starts blending toward gameplay below this distance and is fully there near min_distance.
@export var gameplay_blend_start: float = 110000.0

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

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button_event.pressed:
			_zoom_by(0.78, mouse_button_event.position)
		elif mouse_button_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button_event.pressed:
			_zoom_by(1.0 / 0.78, mouse_button_event.position)
		elif mouse_button_event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			dragging = mouse_button_event.pressed
			last_mouse = mouse_button_event.position
	elif event is InputEventMouseMotion and dragging:
		var mouse_motion_event: InputEventMouseMotion = event as InputEventMouseMotion
		var delta_px: Vector2 = mouse_motion_event.position - last_mouse
		last_mouse = mouse_motion_event.position
		_pan_pixels(delta_px)
	elif event is InputEventPanGesture:
		var pan_event: InputEventPanGesture = event as InputEventPanGesture
		_pan_pixels(pan_event.delta * 28.0)
	elif event is InputEventMagnifyGesture:
		var magnify_event: InputEventMagnifyGesture = event as InputEventMagnifyGesture
		if magnify_event.factor > 0.0:
			_zoom_by(1.0 / magnify_event.factor, magnify_event.position)

func _pan_pixels(delta_px: Vector2) -> void:
	var meters_per_px: float = distance / 900.0
	focus += Vector3(-delta_px.x, 0.0, -delta_px.y) * meters_per_px
	_apply_camera()

func _zoom_by(factor: float, screen_position: Vector2) -> void:
	# Keep the map point under the mouse/fingers anchored while zooming. First
	# project the pointer onto the ground, apply the new camera distance, then
	# compensate the logical focus by the movement of that same screen ray.
	var before: Vector3 = _ground_point(screen_position)
	var old_distance: float = distance
	distance = clampf(distance * factor, min_distance, max_distance)
	if is_equal_approx(distance, old_distance):
		return

	_apply_camera()
	if not before.is_finite():
		return

	var after: Vector3 = _ground_point(screen_position)
	if not after.is_finite():
		return

	var correction: Vector3 = before - after
	correction.y = 0.0
	focus += correction
	_apply_camera()

func _ground_point(screen_position: Vector2) -> Vector3:
	var ray_origin: Vector3 = camera.project_ray_origin(screen_position)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_position)
	if ray_direction.y >= -0.000001:
		return Vector3(INF, INF, INF)
	var t: float = -ray_origin.y / ray_direction.y
	if t <= 0.0:
		return Vector3(INF, INF, INF)
	return ray_origin + ray_direction * t

func _gameplay_blend() -> float:
	if distance >= gameplay_blend_start:
		return 0.0
	var raw: float = 1.0 - inverse_lerp(min_distance, gameplay_blend_start, distance)
	return raw * raw * (3.0 - 2.0 * raw)

func _apply_camera() -> void:
	position = focus
	var blend: float = _gameplay_blend()
	var pitch_degrees: float = lerpf(overview_pitch_degrees, gameplay_pitch_degrees, blend)
	var pitch: float = deg_to_rad(pitch_degrees)
	camera.fov = lerpf(overview_fov, gameplay_fov, blend)

	camera.position = Vector3(0.0, sin(pitch) * distance, cos(pitch) * distance)
	var forward_distance: float = distance * gameplay_forward_look * blend
	var look_target: Vector3 = global_position + Vector3(0.0, 0.0, -forward_distance)
	camera.look_at(look_target, Vector3.UP)

	# Keep the depth buffer tight, but never let the far clip plane cut through
	# ground that is actually visible in the drone camera. At shallow angles the
	# top screen corners can hit the map much farther away than camera distance.
	camera.near = clampf(distance * 0.0025, 5.0, 2500.0)
	var normal_far: float = maxf(25000.0, distance * 3.5)
	camera.far = maxf(normal_far, _required_ground_far() * 1.12)
	view_changed.emit(focus, distance, camera.global_position)

func _required_ground_far() -> float:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return distance * 3.5

	var screen_points: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(viewport_size.x * 0.5, 0.0),
		Vector2(viewport_size.x, 0.0),
		Vector2(viewport_size.x, viewport_size.y),
		Vector2(0.0, viewport_size.y),
	]
	var required: float = distance
	for screen_point in screen_points:
		var ray_origin: Vector3 = camera.project_ray_origin(screen_point)
		var ray_direction: Vector3 = camera.project_ray_normal(screen_point)
		if ray_direction.y >= -0.000001:
			continue
		var t: float = -ray_origin.y / ray_direction.y
		if t <= 0.0:
			continue
		var hit: Vector3 = ray_origin + ray_direction * t
		required = maxf(required, camera.global_position.distance_to(hit))
	return required

func get_ground_view_corners() -> PackedVector3Array:
	# Return where the four viewport corner rays hit the y=0 world plane.
	# Tile streaming can then follow what the camera really sees instead of an
	# arbitrary radius around the logical focus point.
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var screen_corners: Array[Vector2] = [
		Vector2(0.0, 0.0),
		Vector2(viewport_size.x, 0.0),
		Vector2(viewport_size.x, viewport_size.y),
		Vector2(0.0, viewport_size.y),
	]
	var result: PackedVector3Array = PackedVector3Array()
	for screen_point in screen_corners:
		var ray_origin: Vector3 = camera.project_ray_origin(screen_point)
		var ray_direction: Vector3 = camera.project_ray_normal(screen_point)
		if ray_direction.y >= -0.000001:
			continue
		var t: float = -ray_origin.y / ray_direction.y
		if t <= 0.0:
			continue
		result.append(ray_origin + ray_direction * t)
	return result

func set_view(new_focus: Vector3, new_distance: float) -> void:
	focus = Vector3(new_focus.x, 0.0, new_focus.z)
	distance = clampf(new_distance, min_distance, max_distance)
	_apply_camera()

func get_focus_world() -> Vector3:
	return focus

func get_distance() -> float:
	return distance
