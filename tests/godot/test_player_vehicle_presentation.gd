extends SceneTree

## Headless regression for one shared player-car presentation and exact teleport coordinates.
##
## Dependencies:
## - player_vehicle.tscn owns the authoritative player vehicle instance and Drive visual.
## - PlayerMapMarker reuses PlayerCarVisual for Map presentation.
## - GpsRouteDriveRenderAdapter owns Map/Drive visibility and render-local teleport synchronization.

const AdapterScript = preload("res://scripts/gps_route_drive_render_adapter.gd")
const PlayerMapMarkerScript = preload("res://scripts/player_map_marker.gd")
const PlayerCarVisualScript = preload("res://scripts/player_car_visual.gd")

class FakeCameraRig extends Node3D:
	var driving := false
	func get_distance() -> float: return 250.0
	func is_driving_view() -> bool: return driving

class FakeRouteRenderer extends Node3D:
	var height_m := 0.4
	func update_height(_distance_m: float, road_height_m: float) -> void: height_m = road_height_m + 0.4
	func route_height() -> float: return height_m

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://scenes/player_vehicle.tscn") as PackedScene
	_assert(scene != null, "production player vehicle scene loads")
	var player := scene.instantiate() as Node3D
	get_root().add_child(player)
	await process_frame

	var fallback_body := player.get_node_or_null("VisualRoot/Body") as MeshInstance3D
	var drive_car := player.get_node_or_null("VisualRoot/PlayerCarVisual") as Node3D
	_assert(fallback_body != null and not fallback_body.visible, "red fallback body is hidden for the production player vehicle")
	_assert(drive_car != null and drive_car.get_script() == PlayerCarVisualScript, "Drive uses the shared production player-car visual")
	_assert(drive_car.get_node_or_null("Body") is MeshInstance3D, "shared Drive car has recognizable body geometry")

	var marker := PlayerMapMarkerScript.new() as Node3D
	get_root().add_child(marker)
	await process_frame
	var map_car := marker.get_node_or_null("CarVisual") as Node3D
	_assert(map_car != null and map_car.get_script() == PlayerCarVisualScript, "Map reuses the same player-car visual implementation")
	marker.free()

	var rig := FakeCameraRig.new()
	var renderer := FakeRouteRenderer.new()
	var layer := AdapterScript.new() as Node3D
	get_root().add_child(rig)
	get_root().add_child(renderer)
	get_root().add_child(layer)
	layer.set_process(false)
	layer.set("player", player)
	layer.set("_camera_rig", rig)
	layer.set("route_renderer", renderer)
	layer.call("_create_player_marker")

	player.call("set_world_position", Vector3(1200.0, 0.0, -800.0))
	layer.call("set_render_origin_world", Vector3(1000.0, 0.0, -1000.0))
	_assert(_xz_close(player.global_position, Vector3(1200.0, 0.0, -800.0)), "non-zero Drive render origin never mutates authoritative vehicle coordinates")
	var visual_root := player.get_node("VisualRoot") as Node3D
	_assert(_xz_close(visual_root.global_position, Vector3(200.0, 0.0, 200.0)), "Drive visual is render-local to the active origin")

	rig.driving = false
	layer.call("_update_visual_height")
	var production_marker := layer.get_node_or_null("PlayerMapMarker") as Node3D
	_assert(not visual_root.visible, "Map hides the physical Drive visual so no duplicate car is shown")
	_assert(production_marker != null and production_marker.visible, "Map shows exactly the shared map-car presentation")

	rig.driving = true
	layer.call("_update_visual_height")
	_assert(visual_root.visible, "Drive shows the production player-car visual")
	_assert(production_marker != null and not production_marker.visible, "Drive hides the separate Map marker")

	var identity := player
	var target := Vector3(1337.25, 0.0, -642.75)
	_assert(bool(layer.call("teleport_player_to_world", target)), "teleport succeeds with non-zero Drive render origin")
	_assert(layer.get("player") == identity, "teleport preserves the authoritative player vehicle instance")
	_assert(_xz_close(player.global_position, target, 0.001), "teleport lands at the exact requested world X/Z without presentation offset")
	_assert(_xz_close(visual_root.global_position, target - Vector3(1000.0, 0.0, -1000.0), 0.001), "teleport immediately resynchronizes the render-local Drive visual")
	_assert(absf(float(player.call("speed_mps"))) <= 0.001, "teleport resets vehicle speed")

	layer.free()
	renderer.free()
	rig.free()
	player.free()
	print("godot player-vehicle-presentation tests: OK")
	quit(0)

func _xz_close(a: Vector3, b: Vector3, epsilon: float = 0.001) -> bool:
	return absf(a.x - b.x) <= epsilon and absf(a.z - b.z) <= epsilon

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	quit(1)
