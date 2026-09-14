class_name PoliceTacticReservationStore
extends RefCounted

## Reserves abstract police tactic targets so units do not stack on the same action/location.
##
## Dependencies:
## - Stores only caller-provided tactic ids, unit ids and world positions.
## - Owns no routing, Vehicle, observation, rendering or real-world deployment procedure.

var min_separation_m: float = 30.0
var _reservations: Dictionary = {}

func try_reserve(unit_id: StringName, tactic_id: StringName, position: Vector2) -> bool:
	if unit_id == &"" or tactic_id == &"" or not position.is_finite():
		return false
	for reservation_value in _reservations.values():
		var reservation: Dictionary = reservation_value
		if StringName(reservation.get("unit_id", &"")) == unit_id:
			continue
		var other_position: Vector2 = reservation.get("position", Vector2(INF, INF))
		if StringName(reservation.get("tactic_id", &"")) == tactic_id and other_position.is_finite() and other_position.distance_to(position) < min_separation_m:
			return false
	_reservations[unit_id] = {"unit_id": unit_id, "tactic_id": tactic_id, "position": position}
	return true

func release(unit_id: StringName) -> void:
	_reservations.erase(unit_id)

func reservation_for(unit_id: StringName) -> Dictionary:
	return (_reservations.get(unit_id, {}) as Dictionary).duplicate(true)

func count() -> int:
	return _reservations.size()
