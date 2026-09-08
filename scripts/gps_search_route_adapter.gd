extends Node

## Adapts offline search selections into explicit GPS destination/waypoint commands.
##
## Dependencies:
## - Main supplies GpsSearchUi and GpsRouteLayer through setup().
## - Calls only GpsRouteLayer's public destination/waypoint API; owns no route state or search logic.

var _search_ui: Node
var _route_layer: Node

func setup(search_ui: Node, route_layer: Node) -> void:
	_search_ui = search_ui
	_route_layer = route_layer
	if _search_ui != null:
		if not _search_ui.is_connected("destination_selected", _on_destination_selected):
			_search_ui.connect("destination_selected", _on_destination_selected)
		if not _search_ui.is_connected("waypoint_selected", _on_waypoint_selected):
			_search_ui.connect("waypoint_selected", _on_waypoint_selected)

func _on_destination_selected(point: Vector2) -> void:
	_apply_destination(_route_layer, point)

func _on_waypoint_selected(point: Vector2) -> void:
	_apply_waypoint(_route_layer, point)

static func _apply_destination(target_route_layer: Node, point: Vector2) -> bool:
	if target_route_layer == null or not point.is_finite() or not target_route_layer.has_method("set_destination"):
		return false
	return bool(target_route_layer.call("set_destination", point))

static func _apply_waypoint(target_route_layer: Node, point: Vector2) -> bool:
	if target_route_layer == null or not point.is_finite() or not target_route_layer.has_method("add_waypoint"):
		return false
	return bool(target_route_layer.call("add_waypoint", point))
