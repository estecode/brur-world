extends Node3D
class_name PoliceVehicleVisual

## Presents the Swedish police-car profile, emergency-light layout and deterministic flash pattern.
##
## Dependencies:
## - Presentation-only child of Vehicle; reads only Vehicle.profile_id() and receives emergency-light state explicitly.
## - Does not depend on police AI, routing, traffic, input, or vehicle dynamics.

const POLICE_PROFILE_ID: StringName = &"se_police_volvo_v90_cc_d5_2017"
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

var _profile_active: bool = false
var _enabled: bool = false
var _elapsed_s: float = 0.0
var _phase_index: int = 0

func _ready() -> void:
	_sync_parent_profile()
	_apply_phase()

func _process(delta: float) -> void:
	_sync_parent_profile()
	advance_pattern(delta)

func set_police_profile_active(active: bool) -> void:
	if _profile_active == active:
		return
	_profile_active = active
	if not active:
		_enabled = false
		_elapsed_s = 0.0
		_phase_index = 0
	_apply_profile_visibility()
	_apply_phase()

func police_profile_active() -> bool:
	return _profile_active

func set_emergency_lights_active(active: bool) -> void:
	_enabled = active and _profile_active
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

func _sync_parent_profile() -> void:
	var vehicle := get_parent().get_parent()
	if vehicle == null or not vehicle.has_method("profile_id"):
		set_police_profile_active(false)
		return
	set_police_profile_active(StringName(vehicle.call("profile_id")) == POLICE_PROFILE_ID)

func _apply_profile_visibility() -> void:
	var civilian_body := get_node_or_null("../Body") as GeometryInstance3D
	if civilian_body != null:
		civilian_body.visible = not _profile_active
	var livery := get_node_or_null("Livery") as Node3D
	if livery != null:
		livery.visible = _profile_active
	var housing := get_node_or_null("LightBarHousing") as Node3D
	if housing != null:
		housing.visible = _profile_active

func _apply_phase() -> void:
	var phase := FLASH_PATTERN[_phase_index] if _enabled and _profile_active else Vector2i.ZERO
	_set_group_visible("Left", phase.x == 1)
	_set_group_visible("Right", phase.y == 1)

func _set_group_visible(group_name: String, visible: bool) -> void:
	var group := get_node_or_null(group_name) as Node3D
	if group == null:
		return
	group.visible = visible
