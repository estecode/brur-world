extends CanvasLayer

## Presents the camera's current real-world altitude as a compact UI readout.
##
## Dependencies:
## - CameraRig exposes get_altitude() and format_altitude_readout().

@export var camera_rig_path: NodePath

@onready var camera_rig: Node = get_node(camera_rig_path)
@onready var label: Label = $Panel/Label

func _ready() -> void:
	_update_readout()

func _process(_delta: float) -> void:
	_update_readout()

func _update_readout() -> void:
	if camera_rig == null:
		return
	label.text = str(camera_rig.call("format_altitude_readout"))
