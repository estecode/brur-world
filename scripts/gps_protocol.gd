class_name GpsProtocol
extends RefCounted

## Pure native GPS wire request/response conversion.
##
## Dependencies:
## - Uses projected Vector2 stops and Godot's JSON value parser only.
## - Has no SceneTree, UI, rendering, TCP or process dependency.

static func encode_plan(stops: Array[Vector2], preference: String) -> String:
	if stops.size() < 2 or preference.is_empty():
		return ""
	var fields: PackedStringArray = PackedStringArray(["plan", preference, str(stops.size())])
	for point in stops:
		fields.append("%.9f" % point.x)
		fields.append("%.9f" % point.y)
	return " ".join(fields) + "\n"

static func decode_response(line: String) -> Dictionary:
	if line.strip_edges().is_empty():
		return {"valid": false, "error": "empty_response", "payload": {}}
	var parsed: Variant = JSON.parse_string(line)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"valid": false, "error": "invalid_response", "payload": {}}
	return {"valid": true, "error": "", "payload": parsed as Dictionary}
