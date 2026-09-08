class_name GpsRouteModel
extends RefCounted

## Owns GPS destination, waypoint and routing-preference state.
##
## Dependencies:
## - Uses projected Vector2 coordinates and plain strings only.
## - Has no UI, rendering, transport, search or SceneTree dependency.

const ROUTING_PREFERENCES: Array[String] = [
	"fastest",
	"shortest",
	"avoid_small_roads",
	"avoid_major_roads",
]

var _waypoints: Array[Vector2] = []
var _destination: Vector2 = Vector2.ZERO
var _has_destination: bool = false
var _preference: String = "fastest"

func waypoint_count() -> int:
	return _waypoints.size()

func waypoints() -> Array[Vector2]:
	return _waypoints.duplicate()

func add_waypoint(point: Vector2, index: int = -1) -> void:
	if index < 0:
		_waypoints.append(point)
		return
	if index > _waypoints.size():
		push_error("Waypoint index out of range")
		return
	_waypoints.insert(index, point)

func remove_waypoint(index: int) -> bool:
	if index < 0 or index >= _waypoints.size():
		return false
	_waypoints.remove_at(index)
	return true

func clear_waypoints() -> void:
	_waypoints.clear()

func set_destination(point: Vector2) -> void:
	_destination = point
	_has_destination = true

func clear_destination() -> void:
	_has_destination = false

func has_destination() -> bool:
	return _has_destination

func destination() -> Vector2:
	return _destination

func set_preference(value: String) -> bool:
	if not value in ROUTING_PREFERENCES:
		return false
	_preference = value
	return true

func preference() -> String:
	return _preference

func ordered_stops(start: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = [start]
	result.append_array(_waypoints)
	if _has_destination:
		result.append(_destination)
	return result
