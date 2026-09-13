extends SceneTree

## Headless deterministic tests for Drive HUD formatting, layout, road-speed truth, and route ETA.
##
## Dependencies:
## - drive_hud.gd / speed_limit_sign.gd own presentation only.
## - road_speed_limit_query.gd reads BRG1/BRS2 without inventing fallback legal limits.
## - vehicle_route_follower.gd owns remaining route-time state used as optional ETA.

const DriveHudScript = preload("res://scripts/drive_hud.gd")
const RoadSpeedLimitQueryScript = preload("res://scripts/road_speed_limit_query.gd")
const VehicleRouteFollowerScript = preload("res://scripts/vehicle_route_follower.gd")

class FakeWorldCoordinates:
	extends RefCounted
	func world_to_absolute(world_position: Vector3) -> Vector2:
		return Vector2(world_position.x, world_position.z)

class FakeVehicle:
	extends Node3D
	var max_speed_mps: float = 50.0
	var _speed_mps: float = 0.0
	var _heading_rad: float = 0.0
	func set_control_owner(_owner: int) -> void: pass
	func set_control_inputs(_owner: int, _throttle: float, _brake: float, _steering: float) -> bool: return true
	func clear_control_inputs(_owner: int) -> bool: return true
	func heading_rad() -> float: return _heading_rad
	func speed_mps() -> float: return _speed_mps

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_presentation_contracts()
	_test_explicit_speed_limit_query()
	await _test_remaining_route_eta()
	_test_production_scene_structure()
	print("godot Drive HUD tests: OK")
	quit(0)

func _test_presentation_contracts() -> void:
	var hud: CanvasLayer = DriveHudScript.new()
	root.add_child(hud)
	await process_frame
	for pair in [[0.0, "0"], [7.0, "7"], [10.0, "10"], [68.0, "68"], [100.0, "100"], [102.0, "102"], [999.0, "999"]]:
		_assert(str(hud.call("format_speed_kmh", pair[0])) == pair[1], "speed formatting has no leading zeroes for %s" % pair[1])
	_assert(is_equal_approx(float(hud.call("speed_field_width")), 96.0), "speed field reserves one fixed three-digit width")

	hud.call("set_state", {"current_speed_kmh": 7.0, "speed_limit_kmh": 70.0, "eta_seconds": null})
	await process_frame
	var speed_label: Label = hud.call("speed_value_control") as Label
	var speed_left_without_eta := speed_label.global_position.x
	var speed_width_without_eta := speed_label.size.x
	_assert(speed_label.text == "7", "one-digit speed is displayed without a leading zero")
	_assert(not bool(hud.call("eta_visible")), "ETA is hidden when navigation has no ETA")
	_assert(str((hud.call("speed_limit_sign_control") as Control).call("displayed_text")) == "70", "speed-limit sign displays the supplied legal limit")

	hud.call("set_state", {"current_speed_kmh": 102.0, "speed_limit_kmh": 110.0, "eta_seconds": 754.0})
	await process_frame
	_assert(speed_label.text == "102", "three-digit speed fits the same reserved field")
	_assert(is_equal_approx(speed_label.global_position.x, speed_left_without_eta), "speed field position does not move when ETA appears")
	_assert(is_equal_approx(speed_label.size.x, speed_width_without_eta), "speed field width does not change from one to three digits")
	_assert(bool(hud.call("eta_visible")), "ETA is visible when navigation provides one")
	_assert(str(hud.call("format_eta", 754.0)) == "00:12:34", "ETA uses HH:mm:ss")

	hud.call("set_state", {"current_speed_kmh": 68.0, "speed_limit_kmh": null, "eta_seconds": null})
	await process_frame
	_assert(str((hud.call("speed_limit_sign_control") as Control).call("displayed_text")) == "—", "unknown speed limit is explicit rather than fabricated")
	hud.queue_free()
	await process_frame

func _test_explicit_speed_limit_query() -> void:
	var graph_explicit := "user://drive_hud_explicit.brg"
	var snap_explicit := "user://drive_hud_explicit.brs"
	_write_routing_fixture(graph_explicit, snap_explicit, 0)
	var query = RoadSpeedLimitQueryScript.new()
	_assert(query.setup(graph_explicit, snap_explicit, FakeWorldCoordinates.new()), "road speed query opens valid BRG1/BRS2 fixtures")
	var limit: Variant = query.speed_limit_kmh_at(Vector3(150.0, 0.0, 104.0))
	_assert(limit != null and is_equal_approx(float(limit), 50.0), "explicit OSM maxspeed is exposed near the current road")
	_assert(query.speed_limit_kmh_at(Vector3(150.0, 0.0, 180.0)) == null, "distant road does not leak a speed limit")

	var graph_fallback := "user://drive_hud_fallback.brg"
	var snap_fallback := "user://drive_hud_fallback.brs"
	_write_routing_fixture(graph_fallback, snap_fallback, 1)
	var fallback_query = RoadSpeedLimitQueryScript.new()
	_assert(fallback_query.setup(graph_fallback, snap_fallback, FakeWorldCoordinates.new()), "fallback fixture opens")
	_assert(fallback_query.speed_limit_kmh_at(Vector3(150.0, 0.0, 100.0)) == null, "routing fallback speed is not presented as a legal speed limit")

func _test_remaining_route_eta() -> void:
	var vehicle := FakeVehicle.new()
	var follower: Node = VehicleRouteFollowerScript.new()
	vehicle.add_child(follower)
	root.add_child(vehicle)
	await process_frame
	follower.call("set_route", PackedVector3Array([Vector3.ZERO, Vector3(100.0, 0.0, 0.0), Vector3(200.0, 0.0, 0.0)]), PackedFloat32Array([10.0, 10.0, 10.0]))
	_assert(is_equal_approx(float(follower.call("remaining_route_time_s")), 20.0), "route owner exposes deterministic remaining ETA from route geometry/speeds")
	vehicle.global_position = Vector3(50.0, 0.0, 0.0)
	_assert(is_equal_approx(float(follower.call("remaining_route_time_s")), 15.0), "remaining ETA decreases from current vehicle position")
	follower.call("clear_route")
	_assert(float(follower.call("remaining_route_time_s")) < 0.0, "no active route exposes no ETA")
	vehicle.queue_free()
	await process_frame

func _test_production_scene_structure() -> void:
	var packed_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	_assert(packed_scene != null, "production scene parses with Drive HUD")
	var scene: Node = packed_scene.instantiate()
	_assert(scene.get_node_or_null("DriveHud") != null, "production scene composes Drive HUD presentation")
	_assert(scene.get_node_or_null("DriveHudAdapter") != null, "production scene composes a separate HUD state adapter")
	scene.free()

func _write_routing_fixture(graph_path: String, snap_path: String, speed_source: int) -> void:
	var graph := FileAccess.open(graph_path, FileAccess.WRITE)
	graph.store_buffer("BRG1".to_ascii_buffer())
	graph.store_32(2)
	graph.store_32(2)
	_write_node(graph, 1, 100.0, 100.0, 0, 1)
	_write_node(graph, 2, 200.0, 100.0, 1, 1)
	_write_edge(graph, 10, 0, 0, 1, 100.0, 50.0, speed_source)
	_write_edge(graph, 10, 0, 1, 0, 100.0, 50.0, speed_source)
	graph = null

	var snap := FileAccess.open(snap_path, FileAccess.WRITE)
	snap.store_buffer("BRS2".to_ascii_buffer())
	snap.store_float(256.0)
	snap.store_32(1)
	snap.store_32(1)
	snap.store_float(110.0)
	snap.store_32(0)
	snap.store_32(0)
	snap.store_32(0)
	snap.store_32(1)
	snap.store_32(0)
	snap = null

func _write_node(file: FileAccess, osm_id: int, x: float, y: float, adjacency_offset: int, adjacency_count: int) -> void:
	file.store_64(osm_id)
	file.store_double(0.0)
	file.store_double(0.0)
	file.store_float(x)
	file.store_float(y)
	file.store_32(adjacency_offset)
	file.store_32(adjacency_count)

func _write_edge(file: FileAccess, way_id: int, segment_index: int, source_index: int, target_index: int, length_m: float, speed_kmh: float, speed_source: int) -> void:
	file.store_64(way_id)
	file.store_32(segment_index)
	file.store_32(source_index)
	file.store_32(target_index)
	file.store_float(length_m)
	file.store_float(speed_kmh)
	file.store_8(11)
	file.store_8(0)
	file.store_8(0)
	file.store_8(speed_source)
	file.store_8(0)
	file.store_8(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("Drive HUD test failed: " + message)
	quit(1)
