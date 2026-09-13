class_name PoliceUnit
extends RefCounted

## Stores one lightweight persistent police response resource.
##
## Dependencies:
## - Pure domain state; no SceneTree, rendering, routing transport, or UI dependency.
## - PoliceDispatch owns assignment policy and mutates this state through the public API.

var unit_id: String = ""
var role: StringName = &"patrol"
var position: Vector2 = Vector2.ZERO
var current_assignment_id: String = ""


func _init(
	id: String = "",
	unit_role: StringName = &"patrol",
	unit_position: Vector2 = Vector2.ZERO
) -> void:
	unit_id = id
	role = unit_role
	position = unit_position


func is_available() -> bool:
	return current_assignment_id.is_empty()


func is_compatible(required_role: StringName) -> bool:
	return required_role == StringName() or required_role == role


func assign(incident_id: String) -> bool:
	if incident_id.is_empty() or not is_available():
		return false
	current_assignment_id = incident_id
	return true


func release(incident_id: String, new_position: Vector2) -> bool:
	if current_assignment_id != incident_id:
		return false
	position = new_position
	current_assignment_id = ""
	return true


func save_state() -> Dictionary:
	return {
		"unit_id": unit_id,
		"role": String(role),
		"position": [position.x, position.y],
		"current_assignment_id": current_assignment_id,
	}


static func from_state(state: Dictionary) -> PoliceUnit:
	var position_value: Variant = state.get("position", [0.0, 0.0])
	var restored_position := Vector2.ZERO
	if typeof(position_value) == TYPE_ARRAY:
		var coordinates: Array = position_value as Array
		if coordinates.size() >= 2:
			restored_position = Vector2(float(coordinates[0]), float(coordinates[1]))
	var unit := PoliceUnit.new(
		str(state.get("unit_id", "")),
		StringName(str(state.get("role", "patrol"))),
		restored_position
	)
	unit.current_assignment_id = str(state.get("current_assignment_id", ""))
	return unit
