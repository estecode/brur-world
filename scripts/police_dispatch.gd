class_name PoliceDispatch
extends RefCounted

## Owns finite police-resource assignment, queue priority, travel delay, and release.
##
## Dependencies:
## - Owns PoliceUnit resources and consumes an injected route-estimate Callable.
## - Does not own road/routing truth, GPS transport, SceneTree nodes, rendering, or UI.

const PoliceUnitScript = preload("res://scripts/police_unit.gd")
const TIE_EPSILON: float = 0.000001

var _units: Dictionary = {}
var _pending: Array[Dictionary] = []
var _assignments: Dictionary = {}
var _next_sequence: int = 0


func add_unit(unit) -> bool:
	if unit == null or str(unit.unit_id).is_empty() or _units.has(unit.unit_id):
		return false
	_units[unit.unit_id] = unit
	return true


func get_unit(unit_id: String):
	return _units.get(unit_id)


func submit_incident(
	incident_id: String,
	position: Vector2,
	priority: int = 0,
	required_role: StringName = &"patrol"
) -> bool:
	if incident_id.is_empty() or _assignments.has(incident_id) or _pending_has(incident_id):
		return false
	_pending.append({
		"incident_id": incident_id,
		"position": position,
		"priority": priority,
		"required_role": required_role,
		"sequence": _next_sequence,
	})
	_next_sequence += 1
	return true


func dispatch_pending(route_estimator: Callable) -> Array[Dictionary]:
	var dispatched: Array[Dictionary] = []
	if not route_estimator.is_valid() or _pending.is_empty():
		return dispatched

	_pending.sort_custom(_incident_before)
	var remaining: Array[Dictionary] = []
	for incident in _pending:
		var candidate := _select_unit(incident, route_estimator)
		if candidate.is_empty():
			remaining.append(incident)
			continue
		var unit = _units[candidate["unit_id"]]
		if not unit.assign(str(incident["incident_id"])):
			remaining.append(incident)
			continue
		var assignment := {
			"incident_id": str(incident["incident_id"]),
			"unit_id": str(candidate["unit_id"]),
			"priority": int(incident["priority"]),
			"required_role": StringName(incident["required_role"]),
			"target_position": incident["position"],
			"distance_m": float(candidate["distance_m"]),
			"travel_time_s": float(candidate["travel_time_s"]),
			"remaining_s": float(candidate["travel_time_s"]),
			"arrived": float(candidate["travel_time_s"]) <= 0.0,
		}
		_assignments[assignment["incident_id"]] = assignment
		dispatched.append(assignment.duplicate(true))
	_pending = remaining
	return dispatched


func advance(delta_seconds: float) -> Array[Dictionary]:
	var arrivals: Array[Dictionary] = []
	var delta := maxf(0.0, delta_seconds)
	var incident_ids: Array = _assignments.keys()
	incident_ids.sort()
	for incident_id_value in incident_ids:
		var incident_id := str(incident_id_value)
		var assignment: Dictionary = _assignments[incident_id]
		if bool(assignment.get("arrived", false)):
			continue
		var remaining := maxf(0.0, float(assignment.get("remaining_s", 0.0)) - delta)
		assignment["remaining_s"] = remaining
		if remaining <= 0.0:
			assignment["arrived"] = true
			arrivals.append(assignment.duplicate(true))
		_assignments[incident_id] = assignment
	return arrivals


func release_incident(incident_id: String) -> bool:
	if not _assignments.has(incident_id):
		return false
	var assignment: Dictionary = _assignments[incident_id]
	var unit_id := str(assignment.get("unit_id", ""))
	if not _units.has(unit_id):
		return false
	var unit = _units[unit_id]
	if not unit.release(incident_id, assignment.get("target_position", unit.position)):
		return false
	_assignments.erase(incident_id)
	return true


func assignment_for(incident_id: String) -> Dictionary:
	if not _assignments.has(incident_id):
		return {}
	return (_assignments[incident_id] as Dictionary).duplicate(true)


func pending_incidents() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for incident in _pending:
		result.append(incident.duplicate(true))
	result.sort_custom(_incident_before)
	return result


func available_unit_count(required_role: StringName = StringName()) -> int:
	var count := 0
	for unit in _units.values():
		if unit.is_available() and unit.is_compatible(required_role):
			count += 1
	return count


func save_state() -> Dictionary:
	var units_state: Array[Dictionary] = []
	var unit_ids: Array = _units.keys()
	unit_ids.sort()
	for unit_id in unit_ids:
		units_state.append(_units[unit_id].save_state())
	var pending_state: Array[Dictionary] = []
	for incident in _pending:
		pending_state.append(_serialize_incident(incident))
	var assignments_state: Array[Dictionary] = []
	var incident_ids: Array = _assignments.keys()
	incident_ids.sort()
	for incident_id in incident_ids:
		assignments_state.append(_serialize_assignment(_assignments[incident_id]))
	return {
		"units": units_state,
		"pending": pending_state,
		"assignments": assignments_state,
		"next_sequence": _next_sequence,
	}


func load_state(state: Dictionary) -> void:
	_units.clear()
	_pending.clear()
	_assignments.clear()
	_next_sequence = int(state.get("next_sequence", 0))
	for unit_state_value in state.get("units", []):
		if typeof(unit_state_value) != TYPE_DICTIONARY:
			continue
		var unit = PoliceUnitScript.from_state(unit_state_value as Dictionary)
		if not unit.unit_id.is_empty():
			_units[unit.unit_id] = unit
	for incident_state_value in state.get("pending", []):
		if typeof(incident_state_value) == TYPE_DICTIONARY:
			_pending.append(_deserialize_incident(incident_state_value as Dictionary))
	for assignment_state_value in state.get("assignments", []):
		if typeof(assignment_state_value) != TYPE_DICTIONARY:
			continue
		var assignment := _deserialize_assignment(assignment_state_value as Dictionary)
		var incident_id := str(assignment.get("incident_id", ""))
		if not incident_id.is_empty():
			_assignments[incident_id] = assignment


func _select_unit(incident: Dictionary, route_estimator: Callable) -> Dictionary:
	var best: Dictionary = {}
	var unit_ids: Array = _units.keys()
	unit_ids.sort()
	for unit_id_value in unit_ids:
		var unit_id := str(unit_id_value)
		var unit = _units[unit_id]
		if not unit.is_available() or not unit.is_compatible(StringName(incident["required_role"])):
			continue
		var estimate_value: Variant = route_estimator.call(unit.position, incident["position"], unit.role)
		if typeof(estimate_value) != TYPE_DICTIONARY:
			continue
		var estimate: Dictionary = estimate_value as Dictionary
		if not bool(estimate.get("success", false)):
			continue
		var travel_time_s := float(estimate.get("travel_time_s", -1.0))
		var distance_m := float(estimate.get("distance_m", -1.0))
		if not is_finite(travel_time_s) or not is_finite(distance_m):
			continue
		if travel_time_s < 0.0 or distance_m < 0.0:
			continue
		var candidate := {
			"unit_id": unit_id,
			"travel_time_s": travel_time_s,
			"distance_m": distance_m,
		}
		if best.is_empty() or _candidate_before(candidate, best):
			best = candidate
	return best


func _candidate_before(left: Dictionary, right: Dictionary) -> bool:
	var left_time := float(left["travel_time_s"])
	var right_time := float(right["travel_time_s"])
	if absf(left_time - right_time) > TIE_EPSILON:
		return left_time < right_time
	var left_distance := float(left["distance_m"])
	var right_distance := float(right["distance_m"])
	if absf(left_distance - right_distance) > TIE_EPSILON:
		return left_distance < right_distance
	return str(left["unit_id"]) < str(right["unit_id"])


func _incident_before(left: Dictionary, right: Dictionary) -> bool:
	var left_priority := int(left.get("priority", 0))
	var right_priority := int(right.get("priority", 0))
	if left_priority != right_priority:
		return left_priority > right_priority
	return int(left.get("sequence", 0)) < int(right.get("sequence", 0))


func _pending_has(incident_id: String) -> bool:
	for incident in _pending:
		if str(incident.get("incident_id", "")) == incident_id:
			return true
	return false


func _serialize_incident(incident: Dictionary) -> Dictionary:
	var result := incident.duplicate(true)
	var position: Vector2 = incident.get("position", Vector2.ZERO)
	result["position"] = [position.x, position.y]
	result["required_role"] = String(incident.get("required_role", StringName()))
	return result


func _deserialize_incident(incident: Dictionary) -> Dictionary:
	var result := incident.duplicate(true)
	result["position"] = _vector2_from_state(incident.get("position", [0.0, 0.0]))
	result["required_role"] = StringName(str(incident.get("required_role", "")))
	return result


func _serialize_assignment(assignment: Dictionary) -> Dictionary:
	var result := assignment.duplicate(true)
	var position: Vector2 = assignment.get("target_position", Vector2.ZERO)
	result["target_position"] = [position.x, position.y]
	result["required_role"] = String(assignment.get("required_role", StringName()))
	return result


func _deserialize_assignment(assignment: Dictionary) -> Dictionary:
	var result := assignment.duplicate(true)
	result["target_position"] = _vector2_from_state(assignment.get("target_position", [0.0, 0.0]))
	result["required_role"] = StringName(str(assignment.get("required_role", "")))
	return result


func _vector2_from_state(value: Variant) -> Vector2:
	if typeof(value) != TYPE_ARRAY:
		return Vector2.ZERO
	var coordinates: Array = value as Array
	if coordinates.size() < 2:
		return Vector2.ZERO
	return Vector2(float(coordinates[0]), float(coordinates[1]))
