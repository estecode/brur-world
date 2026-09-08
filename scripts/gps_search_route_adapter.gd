extends Node

## Thin adapter from offline search selections to the existing GPS route-plan layer.
##
## Dependencies:
## - Receives destination/waypoint Vector2 coordinates from GpsSearchUi.
## - GpsRouteLayer remains the owner of route-plan state and native requests.
## - Contains no search ranking, rendering, snapping or routing logic.

@onready var search_ui: Node = get_node("../GpsSearchUi")
@onready var route_layer: Node = get_node("../GpsRouteLayer")

func _ready() -> void:
	search_ui.connect("destination_selected", _on_destination_selected)
	search_ui.connect("waypoint_selected", _on_waypoint_selected)

func _on_destination_selected(point: Vector2) -> void:
	_apply_destination(route_layer, point)

func _on_waypoint_selected(point: Vector2) -> void:
	_apply_waypoint(route_layer, point)

static func _apply_destination(target_route_layer: Node, point: Vector2) -> bool:
	if target_route_layer == null or not point.is_finite():
		return false
	var model: Variant = target_route_layer.get("route_model")
	if model == null or not model.has_method("set_destination"):
		return false
	model.call("set_destination", point)
	if target_route_layer.has_method("_request_current_plan"):
		target_route_layer.call("_request_current_plan")
	return true

static func _apply_waypoint(target_route_layer: Node, point: Vector2) -> bool:
	if target_route_layer == null or not point.is_finite():
		return false
	var model: Variant = target_route_layer.get("route_model")
	if model == null or not model.has_method("add_waypoint"):
		return false
	model.call("add_waypoint", point)
	if target_route_layer.has_method("_refresh_waypoint_ui"):
		target_route_layer.call("_refresh_waypoint_ui")
	if model.has_method("has_destination") and bool(model.call("has_destination")) and target_route_layer.has_method("_request_current_plan"):
		target_route_layer.call("_request_current_plan")
	return true
