extends Node3D

## Drives the map camera from an explicit real-world altitude with explicit Map/Drive ownership and optional map follow.
##
## Dependencies:
## - camera_altitude_model.gd owns deterministic map-altitude state and readout formatting.
## - Camera3D presents framing; an explicitly wired generic Node3D may be followed in Drive mode or by Map Follow car.
## - Drive render-origin conversion is presentation-only; logical/world coordinates remain owned by WorldCoordinates and the followed target.

signal view_changed(focus_world: Vector3, distance_m: float, camera_world_position: Vector3)
signal map_follow_changed(enabled: bool)

const CameraAltitudeModelScript = preload("res://scripts/camera_altitude_model.gd")
const DRIVE_RENDER_ORIGIN_GRID_M: float = 1024.0

@export var min_altitude_m: float = 50.0
@export var max_altitude_m: float = 1400000.0
@export var start_altitude_m: float = 500000.0
@export var altitude_zoom_sensitivity: float = 0.12
@export var pan_speed_factor: float = 0.8
@export var rotate_speed: float = 1.1
@export var mouse_pan_factor: float = 1.5
@export var mouse_rotate_factor: float = 0.005
@export var tilt_start_altitude_m: float = 250000.0
@export var tilt_end_altitude_m: float = 1500.0
@export var max_tilt_degrees: float = 58.0
@export var gameplay_blend_start_altitude_m: float = 1800.0
@export var gameplay_blend_end_altitude_m: float = 140.0
@export var gameplay_distance_scale: float = 0.42
@export var gameplay_pitch_degrees: float = 56.0
@export var gameplay_look_ahead_m: float = 110.0
@export var gameplay_min_height_m: float = 30.0
@export var drive_distance_m: float = 18.0
@export var drive_height_m: float = 12.0
@export var drive_min_distance_m: float = 9.0
@export var drive_max_distance_m: float = 48.0
@export var drive_look_ahead_m: float = 42.0
@export var drive_fov: float = 58.0
@export var drive_near_m: float = 0.5
@export var drive_far_m: float = 5000.0
@export var mode_transition_seconds: float = 0.65

var focus := Vector3.ZERO
var yaw := 0.0
var altitude_model
var dragging_pan := false
var dragging_rotate := false
var last_mouse := Vector2.ZERO
var _follow_target: Node3D = null
var _drive_mode := false
var _map_follow_enabled := false
var _suppress_map_wasd_until_released := false
var _drive_distance_current_m: float = 18.0
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
	if _drive_mode:
		_apply_drive_camera(delta)
		return
	_handle_map_keyboard(delta)
	if _map_follow_enabled and _has_follow_target():
		_center_on_follow_target()
	else:
		_apply_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if _drive_mode:
				_drive_distance_current_m = clampf(_drive_distance_current_m * 0.88, drive_min_distance_m, drive_max_distance_m)
			else:
				_set_altitude_from_zoom(-1.0)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if _drive_mode:
				_drive_distance_current_m = clampf(_drive_distance_current_m / 0.88, drive_min_distance_m, drive_max_distance_m)
			else:
				_set_altitude_from_zoom(1.0)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			dragging_pan = event.pressed
			last_mouse = event.position
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			dragging_rotate = event.pressed
			last_mouse = event.position
	elif event is InputEventMouseMotion:
		if dragging_pan and not _drive_mode:
			var delta: Vector2 = event.position - last_mouse
			var scale: float = maxf(1.0, get_altitude() * 0.0025) * mouse_pan_factor
			focus += Vector3(-delta.x, 0.0, -delta.y) * scale
			last_mouse = event.position
			_apply_camera()
		elif dragging_rotate and not _drive_mode:
			yaw -= event.relative.x * mouse_rotate_factor
			last_mouse = event.position
			_apply_camera()

func _handle_map_keyboard(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): move.y -= 1.0
	if Input.is_key_pressed(KEY_S): move.y += 1.0
	if Input.is_key_pressed(KEY_A): move.x -= 1.0
	if Input.is_key_pressed(KEY_D): move.x += 1.0
	if move.length_squared() <= 0.0:
		_suppress_map_wasd_until_released = false
		return
	if _suppress_map_wasd_until_released:
		return
	var local_move := move.normalized().rotated(-yaw)
	var speed := maxf(1.0, get_altitude() * pan_speed_factor)
	focus += Vector3(local_move.x, 0.0, local_move.y) * speed * delta

func _set_altitude_from_zoom(direction: float) -> void:
	var factor := exp(direction * altitude_zoom_sensitivity)
	altitude_model.set_altitude(altitude_model.get_altitude() * factor)
	_apply_camera()

func _ground_point(screen_position: Vector2) -> Vector3:
	var ray_origin := camera.project_ray_origin(screen_position)
	var ray_direction := camera.project_ray_normal(screen_position)
	if ray_direction.y >= -0.000001: return Vector3(INF, INF, INF)
	var t := -ray_origin.y / ray_direction.y
	if t <= 0.0: return Vector3(INF, INF, INF)
	return render_to_world_position(ray_origin + ray_direction * t)

func _gameplay_blend() -> float:
	if get_altitude() >= gameplay_blend_start_altitude_m: return 0.0
	if get_altitude() <= gameplay_blend_end_altitude_m: return 1.0
	return 1.0 - inverse_lerp(gameplay_blend_end_altitude_m, gameplay_blend_start_altitude_m, get_altitude())

func _derived_distance() -> float:
	var altitude: float = get_altitude()
	var blend: float = _gameplay_blend()
	return lerpf(altitude, maxf(gameplay_min_height_m, altitude * gameplay_distance_scale), blend)

func _apply_camera() -> void:
	if camera == null or altitude_model == null:
		return
	var altitude: float = float(altitude_model.get_altitude())
	var distance: float = _derived_distance()
	var blend: float = _gameplay_blend()
	var t := clampf(inverse_lerp(tilt_start_altitude_m, tilt_end_altitude_m, altitude), 0.0, 1.0)
	var map_pitch := deg_to_rad(lerpf(0.0, max_tilt_degrees, t))
	var gameplay_pitch := deg_to_rad(gameplay_pitch_degrees)
	var pitch := lerpf(map_pitch, gameplay_pitch, blend)
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw)).normalized()
	var horizontal := sin(pitch) * distance
	var vertical := maxf(2.0, cos(pitch) * distance)
	position = focus - forward * horizontal + Vector3.UP * vertical
	var look_ahead := gameplay_look_ahead_m * blend
	camera.position = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	camera.look_at(focus + forward * look_ahead, Vector3.UP)
	camera.near = maxf(0.1, altitude * 0.000001)
	camera.far = maxf(2000.0, _required_ground_far(distance) * 1.12)
	view_changed.emit(focus, distance, camera.global_position)

func _has_follow_target() -> bool:
	return _follow_target != null and is_instance_valid(_follow_target) and _follow_target.is_inside_tree()

func _target_heading_rad() -> float:
	if _follow_target != null and _follow_target.has_method("heading_rad"): return float(_follow_target.call("heading_rad"))
	return _follow_target.global_rotation.y if _follow_target != null else 0.0

func _drive_camera_height() -> float:
	var extra_distance := maxf(0.0, _drive_distance_current_m - drive_distance_m)
	return drive_height_m + extra_distance * 0.22

func get_render_origin_world() -> Vector3:
	if not _drive_mode or not _has_follow_target():
		return Vector3.ZERO
	var target := _follow_target.global_position
	return Vector3(
		roundf(target.x / DRIVE_RENDER_ORIGIN_GRID_M) * DRIVE_RENDER_ORIGIN_GRID_M,
		0.0,
		roundf(target.z / DRIVE_RENDER_ORIGIN_GRID_M) * DRIVE_RENDER_ORIGIN_GRID_M
	)

func world_to_render_position(world_position: Vector3) -> Vector3:
	return world_position - get_render_origin_world()

func render_to_world_position(render_position: Vector3) -> Vector3:
	return render_position + get_render_origin_world()

func _apply_drive_camera(delta_s: float = 0.0) -> void:
	if not _has_follow_target(): return
	var target_world := _follow_target.global_position
	var target_render := world_to_render_position(target_world)
	var heading := _target_heading_rad()
	var forward := Vector3(-sin(heading), 0.0, -cos(heading)).normalized()
	var extra_distance := maxf(0.0, _drive_distance_current_m - drive_distance_m)
	var height := _drive_camera_height()
	var look_ahead := drive_look_ahead_m + extra_distance * 0.7
	focus = Vector3(target_world.x, 0.0, target_world.z)
	position = target_render
	camera.position = -forward * _drive_distance_current_m + Vector3.UP * height
	camera.fov = drive_fov
	camera.look_at(target_render + forward * look_ahead + Vector3.UP * 2.5, Vector3.UP)
	camera.near = maxf(0.25, drive_near_m)
	camera.far = maxf(camera.near + 100.0, drive_far_m)
	_apply_mode_transition(delta_s)
	view_changed.emit(focus, _drive_distance_current_m, render_to_world_position(camera.global_position))

func _begin_mode_transition() -> void:
	if not is_inside_tree() or camera == null or mode_transition_seconds <= 0.0:
		_transition_active = false
		return
	_transition_from_transform = camera.global_transform
	_transition_from_fov = camera.fov
	_transition_elapsed_s = 0.0
	_transition_active = true

func _rebase_transition_frame(previous_render_origin: Vector3, next_render_origin: Vector3) -> void:
	if not _transition_active:
		return
	_transition_from_transform.origin += previous_render_origin - next_render_origin

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
	var required := distance
	for screen_point in [Vector2.ZERO, Vector2(viewport_size.x * 0.5, 0.0), Vector2(viewport_size.x, 0.0), viewport_size, Vector2(0.0, viewport_size.y)]:
		var ray_origin := camera.project_ray_origin(screen_point)
		var ray_direction := camera.project_ray_normal(screen_point)
		if ray_direction.y >= -0.000001: continue
		var t := -ray_origin.y / ray_direction.y
		if t > 0.0: required = maxf(required, camera.global_position.distance_to(ray_origin + ray_direction * t))
	return required

func get_ground_view_corners() -> PackedVector3Array:
	var viewport_size := get_viewport().get_visible_rect().size
	var result := PackedVector3Array()
	var max_distance := maxf(camera.near, camera.far)
	for screen_point in [Vector2.ZERO, Vector2(viewport_size.x, 0.0), viewport_size, Vector2(0.0, viewport_size.y)]:
		var ray_origin := camera.project_ray_origin(screen_point)
		var ray_direction := camera.project_ray_normal(screen_point)
		var distance := max_distance
		if ray_direction.y < -0.000001:
			var ground_distance := -ray_origin.y / ray_direction.y
			if ground_distance > 0.0:
				distance = minf(ground_distance, max_distance)
		result.append(render_to_world_position(ray_origin + ray_direction * distance))
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
	if _drive_mode:
		set_drive_mode(false)
	if _map_follow_enabled:
		set_map_follow_enabled(false)

func set_drive_mode(enabled: bool) -> void:
	if _drive_mode == enabled: return
	var previous_render_origin := get_render_origin_world()
	_begin_mode_transition()
	_drive_mode = enabled
	var next_render_origin := get_render_origin_world()
	_rebase_transition_frame(previous_render_origin, next_render_origin)
	if enabled:
		_suppress_map_wasd_until_released = false
		set_map_follow_enabled(false)
		_drive_distance_current_m = clampf(drive_distance_m, drive_min_distance_m, drive_max_distance_m)
		_apply_drive_camera()
	else:
		_suppress_map_wasd_until_released = true
		_apply_camera()

func is_drive_mode() -> bool: return _drive_mode
func is_driving_view() -> bool: return _drive_mode

func set_map_follow_enabled(enabled: bool) -> void:
	var next := enabled and _has_follow_target() and not _drive_mode
	if _map_follow_enabled == next: return
	_map_follow_enabled = next
	if _map_follow_enabled:
		_center_on_follow_target()
	map_follow_changed.emit(_map_follow_enabled)

func is_map_follow_enabled() -> bool: return _map_follow_enabled

func _center_on_follow_target() -> void:
	if not _has_follow_target(): return
	var target_position := _follow_target.global_position
	focus = Vector3(target_position.x, 0.0, target_position.z)
	_apply_camera()
func get_focus_world() -> Vector3: return focus
func get_altitude() -> float:
	if _drive_mode:
		return _drive_camera_height()
	return clampf(start_altitude_m, min_altitude_m, max_altitude_m) if altitude_model == null else altitude_model.get_altitude()
func format_altitude_readout() -> String:
	return CameraAltitudeModelScript.format_altitude(get_altitude())
func get_distance() -> float: return _drive_distance_current_m if _drive_mode else _derived_distance()
