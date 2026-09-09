extends Button

## Presents a persistent overlay-window header and owns collapse/restore interaction.
##
## Dependencies:
## - overlay_layout.gd assigns the configured presentation slot.
## - Controls only the visibility of its sibling body Control.

const OverlayLayoutScript = preload("res://scripts/overlay_layout.gd")

@export var target_path: NodePath
@export var title_text: String = "Panel"
@export var slot: int = 0
@export var panel_width: float = 420.0

var _target: Control = null
var _collapsed: bool = false

func _ready() -> void:
	_target = get_node_or_null(target_path) as Control
	pressed.connect(_toggle_collapsed)
	if _target != null:
		OverlayLayoutScript.apply_window(self, _target, slot, panel_width)
	_apply_state()

func set_collapsed(collapsed: bool) -> void:
	_collapsed = collapsed
	_apply_state()

func is_collapsed() -> bool:
	return _collapsed

func _toggle_collapsed() -> void:
	set_collapsed(not _collapsed)

func _apply_state() -> void:
	if _target != null:
		_target.visible = not _collapsed
	text = "%s   %s" % [title_text, "+" if _collapsed else "−"]
	tooltip_text = "Restore %s" % title_text if _collapsed else "Minimize %s" % title_text
