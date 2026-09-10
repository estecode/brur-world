extends Node3D

## Drives the map camera from an explicit real-world altitude with explicit Map/Drive ownership and optional map follow.
##
## Dependencies:
## - camera_altitude_model.gd owns deterministic altitude state and readout formatting.
## - Camera3D presents framing; an explicitly wired generic Node3D may be followed in Drive mode or by Map Follow car.

signal view_changed(focus_world: Vector3, distance_m: float, camera_world_position: Vector3)
signal map_follow_changed(enabled: bool)

const CameraAltitudeModelScript = preload("res://scripts/camera_altitude_model.gd")

@export var min_altitude_m: float = 1000.0
@export var max_altitude_m: float = 1400000.0
@export var start_altitude_m: float = 760000.0
@export var move_speed_factor: float = 0.8
@export var overview_pitch_degrees: float = 72.0
@export var overview_fov: float = 40.0
@export var gameplay_pitch_degrees: float = 45.0
@export var gameplay_fov: float = 52.0
@export var gameplay_forward_look: float = 0.42
@export var gameplay_blend_start_altitude_m: float = 105000.0
@export var drive_height_m: float = 12.0
@export var drive_distance_m: float = 24.0
@export var drive_min_distance_m: float = 18.0
@export var drive_max_distance_m: float = 48.0
@export var drive_look_ahead_m: float = 42.0
@export var drive_fov: float = 58.0
@export var mode_transition_seconds: float = 0.65

var focus := Vector3.ZERO
var dragging := false
var last_mouse := Vector2.ZERO
var altitude_model = null
var _follow_target: Node3D = null
var _drive_mode := false
var _map_follow_enabled := false
var _suppress_map_wasd_until_released := false
var _drive_distance_current_m := 24.0
var _transition_active := false
var _transition_elapsed_s := 0.0
var _transition_from_transform := Transform3D.IDENTITY
var _transition_from_fov := 58.0
@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	altitude_model = CameraAltitudeModelScript.new(min_altitude_m, max_altitude_m, start_altitude_m)
	_drive_distance_current_m = clampf(drive_distance_m, drive_min_distance_m, drive_max_distance_m)
	_apply_camera()

func _process(delta: float) -> void:
	if _drive_mode and _has_follow_target():
		_apply_drive_camera(delta)
		return
	if _transition_active:
		_apply_camera(delta)
		return
	var input := _map_pan_input()
	if input.length_squared() > 0.0:
		_cancel_map_follow()
		input = input.normalized()
		focus += Vector3(input.x, 0.0, input.y) * maxf(250.0, get_distance() * move_speed_factor) * delta
		_apply_camera()
		return
	if _map_follow_enabled and _has_follow_target(): _center_on_follow_target()

func _map_pan_input() -> Vector2:
	if _drive_mode: return Vector2.ZERO
	var input := Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	var wasd_pressed := Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_S)
	if _suppress_map_wasd_until_released:
		if wasd_pressed:
			return input
		_suppress_map_wasd_until_released = false
	if Input.is_key_pressed(KEY_A): input.x -= 1.0
	if Input.is_key_pressed(KEY_D): input.x += 1.0
	if Input.is_key_pressed(KEY_W): input.y -= 1.0
	if Input.is_key_pressed(KEY_S): input.y += 1.0
	return input

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed: _zoom_by(0.78, e.position)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed: _zoom_by(1.0 / 0.78, e.position)
		elif e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			dragging = e.pressed
			last_mouse = e.position
	elif event is InputEventMouseMotion and dragging:
		var e := event as InputEventMouseMotion
		var delta_px := e.position - last_mouse
		last_mouse = e.position
		_pan_pixels(delta_px)
	elif event is InputEventPanGesture: _pan_pixels((event as InputEventPanGesture).delta * 28.0)
	elif event is InputEventMagnifyGesture:
		var e := event as InputEventMagnifyGesture
		if e.factor > 0.0: _zoom_by(1.0 / e.factor, e.position)

func _pan_pixels(delta_px: Vector2) -> void:
	if _drive_mode: return
	_cancel_map_follow()
	focus += Vector3(-delta_px.x, 0.0, -delta_px.y) * (get_distance() / 900.0)
	_apply_camera()

func _zoom_by(factor: float, screen_position: Vector2) -> void:
	if _drive_mode:
		_drive_distance_current_m = clampf(_drive_distance_current_m * factor, drive_min_distance_m, drive_max_distance_m)
		_apply_drive_camera()
		return
	var before := _ground_point(screen_position)
	var old_altitude_m := get_altitude()
	altitude_model.zoom_by(factor)
	if is_equal_approx(get_altitude(), old_altitude_m): return
	_apply_camera()
	if not before.is_finite(): return
	var after := _ground_point(screen_position)
	if not after.is_finite(): return
	var correction := before - after
	correction.y = 0.0
	focus += correction
	_apply_camera()

func _ground_point(screen_position: Vector2) -> Vector3:
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	if ray_direction.y >= -0.000001: return Vector3(INF, INF, INF)
	var t := -ray_origin.y / ray_direction.y
	return Vector3(INF, INF, INF) if t <= 0.0 else ray_origin + ray_direction * t

func _gameplay_blend() -> float:
	if get_altitude() >= gameplay_blend_start_altitude_m: return 0.0
	var raw := 1.0 - inverse_lerp(min_altitude_m, gameplay_blend_start_altitude_m, get_altitude())
	return raw * raw * (3.0 - 2.0 * raw)

func _pitch_radians() -> float:
	return deg_to_rad(lerpf(overview_pitch_degrees, gameplay_pitch_degrees, _gameplay_blend()))

func _derived_distance() -> float:
	var sine_pitch := sin(_pitch_radians())
	return get_altitude() if sine_pitch <= 0.000001 else get_altitude() / sine_pitch

func _apply_camera(delta_s: float = 0.0) -> void:
	if _drive_mode and _has_follow_target():
		_apply_drive_camera(delta_s)
		return
	position = focus
	var blend := _gameplay_blend()
	var pitch := deg_to_rad(lerpf(overview_pitch_degrees, gameplay_pitch_degrees, blend))
	var distance := _derived_distance()
	camera.fov = lerpf(overview_fov, gameplay_fov, blend)
	camera.position = Vector3(0.0, get_altitude(), cos(pitch) * distance)
	camera.look_at(global_position + Vector3(0.0, 0.0, -distance * gameplay_forward_look * blend), Vector3.UP)
	camera.near = clampf(distance * 0.0025, 5.0, 2500.0)
	camera.far = maxf(maxf(25000.0, distance * 3.5), _required_ground_far(distance) * 1.12)
	_apply_mode_transition(delta_s)
	view_changed.emit(focus, distance, camera.global_position)

func _target_heading_rad() -> float:
	if _follow_target != null and _follow_target.has_method("heading_rad"): return float(_follow_target.call("heading_rad"))
	return _follow_target.global_rotation.y if _follow_target != null else 0.0

func _apply_drive_camera(delta_s: float = 0.0) -> void:
	if not _has_follow_target(): return
	var target := _follow_target.global_position
	var heading := _target_heading_rad()
	var forward := Vector3(-sin(heading), 0.0, -cos(heading)).normalized()
	var extra_distance := maxf(0.0, _drive_distance_current_m - drive_distance_m)
	var height := drive_height_m + extra_distance * 0.22
	var look_ahead := drive_look_ahead_m + extra_distance * 0.7
	focus = Vector3(target.x, 0.0, target.z)
	position = target
	camera.position = -forward * _drive_distance_current_m + Vector3.UP * height
	camera.fov = drive_fov
	camera.look_at(target + forward * look_ahead + Vector3.UP * 2.5, Vector3.UP)
	camera.near = 0.1
	camera.far = 25000.0
	_apply_mode_transition(delta_s)
	view_changed.emit(focus, _drive_distance_current_m, camera.global_position)

func _begin_mode_transition() -> void:
	if not is_inside_tree() or camera == null or mode_transition_seconds <= 0.0:
		_transition_active = false
		return
	_transition_from_transform = camera.global_transform
	_transition_from_fov = camera.fov
	_transition_elapsed_s = 0.0
	_transition_active = true

func _apply_mode_transition(delta_s: float) -> void:
	if not _transition_active: return
	var desired_transform := camera.global_transform
	var desired_fov := camera.fov
	_transition_elapsed_s += maxf(0.0, delta_s)
	var raw := clampf(_transition_elapsed_s / maxf(0.001, mode_transition_seconds), 0.0, 1.0)
	var eased := raw * raw * (3.0 - 2.0 * raw)
	camera.global_transform = _transition_from_transform.interpolate_with(desired_transform, eased)
	camera.fov = lerpf(_transition_from_fov, desired_fov, eased)
	if raw >= 1.0: _transition_active = false

func _required_ground_far(distance: float) -> float:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0: return distance * 3.5
	var points: Array[Vector2] = [Vector2.ZERO, Vector2(viewport_size.x * 0.5, 0.0), Vector2(viewport_size.x, 0.0), viewport_size, Vector2(0.0, viewport_size.y)]
	var required := distance
	for screen_point in points:
		var ray_origin := camera.project_ray_origin(screen_point)
		var ray_direction := camera.project_ray_normal(screen_point)
		if ray_direction.y >= -0.000001: continue
		var t := -ray_origin.y / ray_direction.y
		if t > 0.0: required = maxf(required, camera.global_position.distance_to(ray_origin + ray_direction * t))
	return required

func get_ground_view_corners() -> PackedVector3Array:
	var viewport_size := get_viewport().get_visible_rect().size
	var result := PackedVector3Array()
	for screen_point in [Vector2.ZERO, Vector2(viewport_size.x, 0.0), viewport_size, Vector2(0.0, viewport_size.y)]:
		var ray_origin := camera.project_ray_origin(screen_point)
		var ray_direction := camera.project_ray_normal(screen_point)
		if ray_direction.y >= -0.000001: continue
		var t := -ray_origin.y / ray_direction.y
		if t > 0.0: result.append(ray_origin + ray_direction * t)
	return result

func set_view_altitude(new_focus: Vector3, new_altitude_m: float) -> void:
	focus = Vector3(new_focus.x, 0.0, new_focus.z)
	altitude_model.set_altitude(new_altitude_m)
	_apply_camera()

func set_altitude(new_altitude_m: float) -> void:
	altitude_model.set_altitude(new_altitude_m)
	_apply_camera()

func set_follow_target(target: Node3D) -> void:
	_follow_target = target
	if (_drive_mode or _map_follow_enabled) and is_inside_tree() and _has_follow_target():
		if _drive_mode: _apply_drive_camera()
		else: _center_on_follow_target()

func clear_follow_target() -> void:
	_follow_target = null
	set_map_follow_enabled(false)

func set_drive_mode(enabled: bool) -> void:
	if _drive_mode == enabled: return
	_begin_mode_transition()
	_drive_mode = enabled
	if enabled:
		_suppress_map_wasd_until_released = false
		set_map_follow_enabled(false)
	else:
		_suppress_map_wasd_until_released = true
	if is_inside_tree() and _drive_mode and _has_follow_target(): _apply_drive_camera()
	elif is_inside_tree(): _apply_camera()

func is_driving_view() -> bool: return _drive_mode
func is_mode_transition_active() -> bool: return _transition_active
func get_drive_distance() -> float: return _drive_distance_current_m

func set_map_follow_enabled(enabled: bool) -> void:
	var next_enabled := enabled and not _drive_mode and _has_follow_target()
	if _map_follow_enabled == next_enabled: return
	_map_follow_enabled = next_enabled
	map_follow_changed.emit(_map_follow_enabled)
	if _map_follow_enabled and is_inside_tree(): _center_on_follow_target()

func is_map_follow_enabled() -> bool: return _map_follow_enabled
func _cancel_map_follow() -> void:
	if _map_follow_enabled: set_map_follow_enabled(false)
func _has_follow_target() -> bool: return _follow_target != null and is_instance_valid(_follow_target)
func _center_on_follow_target() -> void:
	if not _has_follow_target(): return
	var target_position := _follow_target.global_position
	focus = Vector3(target_position.x, 0.0, target_position.z)
	_apply_camera()
func get_focus_world() -> Vector3: return focus
func get_altitude() -> float: return clampf(start_altitude_m, min_altitude_m, max_altitude_m) if altitude_model == null else altitude_model.get_altitude()
func format_altitude_readout() -> String: return CameraAltitudeModelScript.format_altitude(get_altitude()) if altitude_model == null else altitude_model.format_readout()
func get_distance() -> float: return _drive_distance_current_m if _drive_mode else _derived_distance()