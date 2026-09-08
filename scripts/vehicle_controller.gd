extends Node
class_name VehicleController

## Base controller contract for producing control intent for a Vehicle.
##
## Dependencies:
## - Expects a Vehicle as parent or assigned vehicle_path.
## - Owns no vehicle physics and does not know whether the caller is player, traffic, police, or GPS.

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
		_clear_owned_controls()
		return
	_apply_controls()

func _apply_controls() -> void:
	_clear_owned_controls()

func _clear_owned_controls() -> void:
	pass

func _resolve_vehicle() -> Vehicle:
	if not vehicle_path.is_empty():
		var node: Node = get_node_or_null(vehicle_path)
		if node is Vehicle:
			return node as Vehicle
	var parent_node: Node = get_parent()
	if parent_node is Vehicle:
		return parent_node as Vehicle
	return null
