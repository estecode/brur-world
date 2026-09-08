class_name GpsInputAdapter
extends RefCounted

## Converts Godot mouse/modifier input into explicit GPS route-model commands.
##
## Dependencies:
## - Consumes InputEvent plus an already-converted projected coordinate.
## - Has no route model, TCP, rendering or UI ownership.

const COMMAND_DESTINATION: String = "destination"
const COMMAND_WAYPOINT: String = "waypoint"

static func command_from_mouse(event: InputEvent, gui_blocked: bool, absolute_position: Vector2) -> Dictionary:
	if gui_blocked or not absolute_position.is_finite() or not (event is InputEventMouseButton):
		return {}
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or not mouse_event.pressed or not mouse_event.shift_pressed:
		return {}
	var command_type := COMMAND_WAYPOINT if mouse_event.ctrl_pressed or mouse_event.meta_pressed else COMMAND_DESTINATION
	return {
		"type": command_type,
		"point": absolute_position,
	}
