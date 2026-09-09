extends Node
class_name VehicleController

## Base controller contract for producing control intent for the parent vehicle adapter.
##
## Dependencies:
## - Expects a vehicle-compatible parent or assigned vehicle_path exposing the production control API.
## - Owns no vehicle physics and does not know whether commands come from player, traffic, police, or GPS.

@export var vehicle_path: NodePath
@export var enabled: bool = true

var vehicle: Node = null

func _ready() -> void:
	vehicle = _resolve_vehicle()
	if vehicle == null:
		push_error("VehicleController requires a vehicle-compatible parent or vehicle_path")
		set_physics_process(false)

func _physics_process(_delta: float) -> void:
	if vehicle == null:
		return
	if not enabled:
		_clear_owned_controls()
		return
	_apply_controls()

func _apply_controls() -> void:
	_clear_owned_controls()

func _clear_owned_controls() -> void:
	pass

func _resolve_vehicle() -> Node:
	if not vehicle_path.is_empty():
		var node: Node = get_node_or_null(vehicle_path)
		if _is_vehicle_adapter(node):
			return node
	var parent_node: Node = get_parent()
	if _is_vehicle_adapter(parent_node):
		return parent_node
	return null

func _is_vehicle_adapter(node: Node) -> bool:
	return node != null \
		and node.has_method("set_control_inputs") \
		and node.has_method("clear_control_inputs") \
		and node.has_method("control_owner")
