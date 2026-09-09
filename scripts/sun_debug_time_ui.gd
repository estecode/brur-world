extends VBoxContainer
class_name SunDebugTimeUi

## Lets debug UI override the sun's date/time without mutating the authoritative WorldClock.
## Dependencies: an explicitly configured SunRuntimeController plus owned CheckButton/SpinBox children.

@export_node_path("Node") var sun_controller_path: NodePath

@onready var override_toggle: CheckButton = $OverrideToggle
@onready var year_input: SpinBox = $TimeRow/Year
@onready var month_input: SpinBox = $TimeRow/Month
@onready var day_input: SpinBox = $TimeRow/Day
@onready var hour_input: SpinBox = $TimeRow/Hour
@onready var minute_input: SpinBox = $TimeRow/Minute

var _sun_controller: Node

func _ready() -> void:
	_sun_controller = get_node_or_null(sun_controller_path)
	if _sun_controller == null:
		push_error("SunDebugTimeUi requires SunRuntimeController")
		return
	override_toggle.toggled.connect(_on_override_toggled)
	for input in [year_input, month_input, day_input, hour_input, minute_input]:
		input.value_changed.connect(_on_time_value_changed)
	_update_input_enabled()
	_apply_override()

func _on_override_toggled(_enabled: bool) -> void:
	_update_input_enabled()
	_apply_override()

func _on_time_value_changed(_value: float) -> void:
	_apply_override()

func _update_input_enabled() -> void:
	var enabled := override_toggle.button_pressed
	for input in [year_input, month_input, day_input, hour_input, minute_input]:
		input.editable = enabled

func _apply_override() -> void:
	if _sun_controller == null:
		return
	if not override_toggle.button_pressed:
		_sun_controller.call("clear_time_override")
		return
	_sun_controller.call("set_time_override", {
		"year": int(year_input.value),
		"month": int(month_input.value),
		"day": int(day_input.value),
		"hour": int(hour_input.value),
		"minute": int(minute_input.value),
		"second": 0,
		"utc_offset_hours": 0.0,
	})
