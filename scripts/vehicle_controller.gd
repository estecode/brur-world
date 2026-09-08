extends Node
class_name VehicleController

## Base controller contract for driving a Vehicle.
##
## Dependencies:
## - Expects a Vehicle as parent or assigned vehicle_path.
## - Does not know whether commands come from a player, traffic AI, police AI, or another system.

@export var vehicle_path: NodePath
@export var enabled: bool = true

var vehicle: Vehicle = null

func _ready() -> void:
	vehicle = _resolve_vehicle()
	if vehicle == null:
		push_error("VehicleController requires a Vehicle parent or vehicle_path")
		set_physics_process(false)

func _physics_process(_delta: float) -> void:
	if vehicle == null:
		return
	if not enabled:
		vehicle.clear_control_inputs()
		return
	_apply_controls()

func _apply_controls() -> void:
	vehicle.clear_control_inputs()

func _resolve_vehicle() -> Vehicle:
	if not vehicle_path.is_empty():
		var node: Node = get_node_or_null(vehicle_path)
		if node is Vehicle:
			return node as Vehicle
	var parent_node: Node = get_parent()
	if parent_node is Vehicle:
		return parent_node as Vehicle
	return null
