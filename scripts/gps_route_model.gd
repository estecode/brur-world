class_name GpsRouteModel
extends RefCounted

## Owns GPS waypoint/destination state without UI, rendering or transport.
##
## Dependencies:
## - Uses only projected Vector2 coordinates.
## - GpsRouteLayer supplies the current start position and sends ordered_stops() to native GPS.

var _waypoints: Array[Vector2] = []
var _destination: Vector2 = Vector2.ZERO
var _has_destination: bool = false

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

func ordered_stops(start: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = [start]
	result.append_array(_waypoints)
	if _has_destination:
		result.append(_destination)
	return result
