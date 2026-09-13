extends Node3D
class_name PoliceVehicleVisual

## Presents the Swedish police-car emergency-light layout and deterministic flash pattern.
##
## Dependencies:
## - Presentation-only child of Vehicle; receives light state explicitly from the Vehicle adapter.
## - Does not depend on police AI, routing, traffic, input, or vehicle dynamics.

const FLASH_STEP_S: float = 0.12
const FLASH_PATTERN: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(0, 0),
	Vector2i(1, 0),
	Vector2i(0, 0),
	Vector2i(0, 1),
	Vector2i(0, 0),
	Vector2i(0, 1),
	Vector2i(0, 0),
]

var _enabled: bool = false
var _elapsed_s: float = 0.0
var _phase_index: int = 0

func _ready() -> void:
	_apply_phase()

func _process(delta: float) -> void:
	advance_pattern(delta)

func set_emergency_lights_active(active: bool) -> void:
	if _enabled == active:
		return
	_enabled = active
	_elapsed_s = 0.0
	_phase_index = 0
	_apply_phase()

func emergency_lights_active() -> bool:
	return _enabled

func flash_phase_index() -> int:
	return _phase_index

func advance_pattern(delta: float) -> void:
	if not _enabled or delta <= 0.0:
		return
	_elapsed_s += delta
	while _elapsed_s >= FLASH_STEP_S:
		_elapsed_s -= FLASH_STEP_S
		_phase_index = (_phase_index + 1) % FLASH_PATTERN.size()
	_apply_phase()

func _apply_phase() -> void:
	var phase := FLASH_PATTERN[_phase_index] if _enabled else Vector2i.ZERO
	_set_group_visible("Left", phase.x == 1)
	_set_group_visible("Right", phase.y == 1)

func _set_group_visible(group_name: String, visible: bool) -> void:
	var group := get_node_or_null(group_name) as Node3D
	if group == null:
		return
	group.visible = visible
