extends Node3D

## Drives the map camera from an explicit real-world altitude while preserving overview/gameplay framing.
##
## Dependencies:
## - camera_altitude_model.gd owns deterministic altitude state and readout formatting.
## - Camera3D presents the derived position/FOV; no world-coordinate, cloud, or weather logic lives here.

const CameraAltitudeModelScript = preload("res://scripts/camera_altitude_model.gd")

@export var min_altitude_m: float = 1000.0
@export var max_altitude_m: float = 1400000.0
@export var start_altitude_m: float = 760000.0
@export var move_speed_factor: float = 0.8

# Zoomed-out Sweden overview.
@export var overview_pitch_degrees: float = 72.0
@export var overview_fov: float = 40.0

# Zoomed-in gameplay/drone framing.
@export var gameplay_pitch_degrees: float = 45.0
@export var gameplay_fov: float = 52.0
@export var gameplay_forward_look: float = 0.42

# Camera starts blending toward gameplay below this altitude and is fully there near min_altitude_m.
@export var gameplay_blend_start_altitude_m: float = 105000.0

var focus: Vector3 = Vector3.ZERO
var dragging: bool = false
var last_mouse: Vector2 = Vector2.ZERO
var altitude_model = null

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	altitude_model = CameraAltitudeModelScript.new(min_altitude_m, max_altitude_m, start_altitude_m)
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
		var speed: float = maxf(250.0, get_distance() * move_speed_factor)
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
	var meters_per_px: float = get_distance() / 900.0
	focus += Vector3(-delta_px.x, 0.0, -delta_px.y) * meters_per_px
	_apply_camera()

func _zoom_by(factor: float, screen_position: Vector2) -> void:
	# Keep the map point under the mouse/fingers anchored while zooming. Altitude
	# is the authoritative zoom value; camera boom distance is derived from it.
	var before: Vector3 = _ground_point(screen_position)
	var old_altitude_m: float = get_altitude()
	altitude_model.zoom_by(factor)
	if is_equal_approx(get_altitude(), old_altitude_m):
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
	var altitude_m: float = get_altitude()
	if altitude_m >= gameplay_blend_start_altitude_m:
		return 0.0
	var raw: float = 1.0 - inverse_lerp(min_altitude_m, gameplay_blend_start_altitude_m, altitude_m)
	return raw * raw * (3.0 - 2.0 * raw)

func _pitch_radians() -> float:
	return deg_to_rad(lerpf(overview_pitch_degrees, gameplay_pitch_degrees, _gameplay_blend()))

func _derived_distance() -> float:
	var sine_pitch: float = sin(_pitch_radians())
	if sine_pitch <= 0.000001:
		return get_altitude()
	return get_altitude() / sine_pitch

func _apply_camera() -> void:
	position = focus
	var blend: float = _gameplay_blend()
	var pitch_degrees: float = lerpf(overview_pitch_degrees, gameplay_pitch_degrees, blend)
	var pitch: float = deg_to_rad(pitch_degrees)
	var distance: float = _derived_distance()
	camera.fov = lerpf(overview_fov, gameplay_fov, blend)

	camera.position = Vector3(0.0, get_altitude(), cos(pitch) * distance)
	var forward_distance: float = distance * gameplay_forward_look * blend
	var look_target: Vector3 = global_position + Vector3(0.0, 0.0, -forward_distance)
	camera.look_at(look_target, Vector3.UP)

	# Keep the depth buffer tight, but never let the far clip plane cut through
	# ground that is actually visible in the drone camera. At shallow angles the
	# top screen corners can hit the map much farther away than camera distance.
	camera.near = clampf(distance * 0.0025, 5.0, 2500.0)
	var normal_far: float = maxf(25000.0, distance * 3.5)
	camera.far = maxf(normal_far, _required_ground_far(distance) * 1.12)

func _required_ground_far(distance: float) -> float:
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

func set_view_altitude(new_focus: Vector3, new_altitude_m: float) -> void:
	focus = Vector3(new_focus.x, 0.0, new_focus.z)
	altitude_model.set_altitude(new_altitude_m)
	_apply_camera()

func set_altitude(new_altitude_m: float) -> void:
	altitude_model.set_altitude(new_altitude_m)
	_apply_camera()

func get_focus_world() -> Vector3:
	return focus

func get_altitude() -> float:
	if altitude_model == null:
		return clampf(start_altitude_m, min_altitude_m, max_altitude_m)
	return altitude_model.get_altitude()

func format_altitude_readout() -> String:
	if altitude_model == null:
		return CameraAltitudeModelScript.format_altitude(get_altitude())
	return altitude_model.format_readout()

func get_distance() -> float:
	return _derived_distance()
