extends Node3D

## Drives the map camera from an explicit real-world altitude with explicit Map/Drive ownership and optional map follow.
##
## Dependencies:
## - camera_altitude_model.gd owns deterministic map-altitude state and readout formatting.
## - Camera3D presents framing; an explicitly wired generic Node3D may be followed in Drive mode or by Map Follow car.
## - Drive render-origin conversion is presentation-only; logical/world coordinates remain owned by WorldCoordinates and the followed target.
## - Building streaming may query a stable Drive ground radius that is independent of visual mode-transition interpolation.

signal view_changed(focus_world: Vector3, distance_m: float, camera_world_position: Vector3)
signal map_follow_changed(enabled: bool)

const CameraAltitudeModelScript = preload("res://scripts/camera_altitude_model.gd")
const DRIVE_RENDER_ORIGIN_GRID_M: float = 1024.0

@export var min_altitude_m: float = 50.0
@export var max_altitude_m: float = 1400000.0
@export var start_altitude_m: float = 760000.0
@export var move_speed_factor: float = 0.8
@export var overview_pitch_degrees: float = 72.0
@export var overview_fov: float = 40.0
@export var gameplay_pitch_degrees: float = 45.0
@export var gameplay_fov: float = 52.0
@export var gameplay_forward_look: float = 0.42
@export var gameplay_blend_start_altitude_m: float = 105000.0
@export var low_altitude_blend_end_m: float = 750.0
@export var low_altitude_pitch_degrees: float = 58.0
@export var low_altitude_forward_look: float = 0.18
@export var drive_height_m: float = 12.0
@export var drive_distance_m: float = 24.0
@export var drive_min_distance_m: float = 18.0
@export var drive_max_distance_m: float = 48.0
@export var drive_look_ahead_m: float = 42.0
@export var drive_fov: float = 58.0
@export var drive_near_m: float = 0.5
@export var drive_far_m: float = 5000.0
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
			return Vector2.ZERO
		_suppress_map_wasd_until_released = false
	if Input.is_key_pressed(KEY_A): input.x -= 1.0
	if Input.is_key_pressed(KEY_D): input.x += 1.0
	if Input.is_key_pressed(KEY_W): input.y -= 1.0
	if Input.is_key_pressed(KEY_S): input.y += 1.0
	return input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			last_mouse = event.position
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if _drive_mode:
				_drive_distance_current_m = maxf(drive_min_distance_m, _drive_distance_current_m * 0.9)
				_apply_drive_camera()
			else:
				set_altitude(get_altitude() * 0.8)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if _drive_mode:
				_drive_distance_current_m = minf(drive_max_distance_m, _drive_distance_current_m * 1.1)
				_apply_drive_camera()
			else:
				set_altitude(get_altitude() * 1.25)
	elif event is InputEventMouseMotion and dragging and not _drive_mode:
		_cancel_map_follow()
		var delta := event.position - last_mouse
		last_mouse = event.position
		var world_per_pixel := maxf(0.5, get_distance() * 0.0012)
		focus += Vector3(-delta.x * world_per_pixel, 0.0, -delta.y * world_per_pixel)
		_apply_camera()

func _apply_camera(delta_s: float = 0.0) -> void:
	if _drive_mode:
		_apply_drive_camera(delta_s)
		return
	var altitude := get_altitude()
	var distance := _derived_distance()
	var pitch := deg_to_rad(_derived_pitch_degrees())
	var forward_look := _derived_forward_look()
	var y := sin(pitch) * distance
	var back := cos(pitch) * distance
	position = Vector3(focus.x, 0.0, focus.z)
	camera.position = Vector3(0.0, y, back)
	camera.fov = _derived_fov()
	camera.look_at(Vector3(0.0, 0.0, -distance * forward_look), Vector3.UP)
	camera.near = maxf(5.0, altitude * 0.00002)
	camera.far = maxf(altitude * 4.0, _required_ground_far(distance) * 1.1)
	_apply_mode_transition(delta_s)
	view_changed.emit(focus, distance, camera.global_position)

func _derived_distance() -> float:
	var altitude := get_altitude()
	var pitch := deg_to_rad(_derived_pitch_degrees())
	return altitude / maxf(0.08, sin(pitch))

func _derived_pitch_degrees() -> float:
	var altitude := get_altitude()
	if altitude >= gameplay_blend_start_altitude_m:
		return overview_pitch_degrees
	if altitude <= low_altitude_blend_end_m:
		return low_altitude_pitch_degrees
	var t := inverse_lerp(low_altitude_blend_end_m, gameplay_blend_start_altitude_m, altitude)
	return lerpf(low_altitude_pitch_degrees, gameplay_pitch_degrees, t)

func _derived_fov() -> float:
	var altitude := get_altitude()
	if altitude >= gameplay_blend_start_altitude_m:
		return overview_fov
	if altitude <= low_altitude_blend_end_m:
		return gameplay_fov
	var t := inverse_lerp(low_altitude_blend_end_m, gameplay_blend_start_altitude_m, altitude)
	return lerpf(gameplay_fov, overview_fov, t)

func _derived_forward_look() -> float:
	var altitude := get_altitude()
	if altitude >= gameplay_blend_start_altitude_m:
		return 0.0
	if altitude <= low_altitude_blend_end_m:
		return low_altitude_forward_look
	var t := inverse_lerp(low_altitude_blend_end_m, gameplay_blend_start_altitude_m, altitude)
	return lerpf(low_altitude_forward_look, gameplay_forward_look, t)

func _drive_camera_height() -> float:
	return maxf(2.0, drive_height_m + maxf(0.0, _drive_distance_current_m - drive_distance_m) * 0.18)

func _target_heading_rad() -> float:
	if not _has_follow_target(): return 0.0
	return _follow_target.rotation.y

func get_render_origin_world() -> Vector3:
	if not _drive_mode or not _has_follow_target():
		return Vector3.ZERO
	var target_world := _follow_target.global_position
	return Vector3(
		floorf(target_world.x / DRIVE_RENDER_ORIGIN_GRID_M) * DRIVE_RENDER_ORIGIN_GRID_M,
		0.0,
		floorf(target_world.z / DRIVE_RENDER_ORIGIN_GRID_M) * DRIVE_RENDER_ORIGIN_GRID_M
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
	# Drive mode renders in a presentation-local frame around the followed target.
	# Logical world coordinates remain untouched while GPU-facing transforms stay
	# near zero, preserving both spatial truth and near-ground float precision.
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

func get_streaming_ground_radius_m() -> float:
	# Drive streaming must not inherit the transient Map->Drive camera transform.
	# The production far plane plus chase offset bounds every Drive ground sample
	# independently of heading and the visual mode transition.
	if _drive_mode:
		return maxf(camera.near + 100.0, drive_far_m) + maxf(0.0, _drive_distance_current_m)
	var radius_m := 0.0
	for point in get_ground_view_corners():
		radius_m = maxf(radius_m, Vector2(point.x - focus.x, point.z - focus.z).length())
	return radius_m

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
	var previous_render_origin := get_render_origin_world()
	_begin_mode_transition()
	_drive_mode = enabled
	var next_render_origin := get_render_origin_world()
	_rebase_transition_frame(previous_render_origin, next_render_origin)
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
func get_altitude() -> float:
	# The altitude model intentionally keeps the Map zoom while Drive mode owns a
	# close chase camera. Consumers that stream presentation (buildings, etc.)
	# need the effective camera altitude, not the retained Map altitude.
	if _drive_mode:
		return _drive_camera_height()
	return clampf(start_altitude_m, min_altitude_m, max_altitude_m) if altitude_model == null else altitude_model.get_altitude()
func format_altitude_readout() -> String:
	return CameraAltitudeModelScript.format_altitude(get_altitude())
func get_distance() -> float: return _drive_distance_current_m if _drive_mode else _derived_distance()
