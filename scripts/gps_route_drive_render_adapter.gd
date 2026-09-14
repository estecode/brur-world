extends "res://scripts/gps_route_layer.gd"

## Adapts production GPS route presentation, player-car visibility and ground picking to the Drive render-local frame.
##
## Dependencies:
## - Inherits the production GpsRouteLayer behavior unchanged for logical routing/player state.
## - CameraRig owns render-to-world conversion; GpsRouteRenderer remains the production route renderer.
## - Player vehicle keeps authoritative world coordinates; this adapter only switches Map/Drive presentation and render-local transforms.

var _drive_render_origin_world := Vector3.ZERO

func set_render_origin_world(render_origin: Vector3) -> void:
	_drive_render_origin_world = Vector3(render_origin.x, 0.0, render_origin.z)
	if route_renderer != null:
		route_renderer.position = Vector3(-_drive_render_origin_world.x, 0.0, -_drive_render_origin_world.z)
	_sync_player_render_origin()

func _create_modules() -> void:
	super._create_modules()
	set_render_origin_world(_drive_render_origin_world)

func _update_visual_height() -> void:
	super._update_visual_height()
	if player == null:
		return
	var driving_view := false
	if _camera_rig != null and _camera_rig.has_method("is_driving_view"):
		driving_view = bool(_camera_rig.call("is_driving_view"))
	var visual_root := player.get_node_or_null("VisualRoot") as Node3D
	if visual_root != null:
		visual_root.visible = driving_view
	_sync_player_render_origin()

func teleport_player_to_world(world_position: Vector3) -> bool:
	var original_player := player
	var teleported := super.teleport_player_to_world(world_position)
	if teleported and player == original_player:
		_sync_player_render_origin()
	return teleported

func _screen_to_ground(screen_position: Vector2) -> Vector3:
	if _camera == null:
		return Vector3(INF, INF, INF)
	var ray_origin := _camera.project_ray_origin(screen_position)
	var ray_direction := _camera.project_ray_normal(screen_position)
	if ray_direction.y >= -0.000001:
		return Vector3(INF, INF, INF)
	var t := -ray_origin.y / ray_direction.y
	if t <= 0.0:
		return Vector3(INF, INF, INF)
	var render_hit := ray_origin + ray_direction * t
	if _camera_rig != null and _camera_rig.has_method("render_to_world_position"):
		return _camera_rig.call("render_to_world_position", render_hit)
	return render_hit

func _sync_player_render_origin() -> void:
	if player != null and player.has_method("set_render_origin_world"):
		player.call("set_render_origin_world", _drive_render_origin_world)
