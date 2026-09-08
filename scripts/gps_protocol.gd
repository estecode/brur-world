class_name GpsProtocol
extends RefCounted

## Pure text protocol encoder for native GPS route-plan requests.
##
## Dependencies:
## - No Godot scene/UI/network dependency; consumes projected Vector2 stops.
## - Native gps_route_server.cpp accepts the same one-line protocol.

static func encode_plan(stops: Array[Vector2], preference: String) -> String:
	if stops.size() < 2 or preference.is_empty():
		return ""
	var fields: PackedStringArray = PackedStringArray(["plan", preference, str(stops.size())])
	for point in stops:
		fields.append("%.9f" % point.x)
		fields.append("%.9f" % point.y)
	return " ".join(fields) + "\n"
