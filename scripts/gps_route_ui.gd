class_name GpsRouteUi
extends CanvasLayer

## Presents GPS status, routing preference and waypoint controls.
##
## Dependencies:
## - Emits user intent only; route-plan state remains in GpsRouteModel.
## - Has no TCP, rendering, search-ranking or routing dependency.

signal preference_selected(preference: String)
signal remove_waypoint_requested(index: int)
signal clear_waypoints_requested

const ROUTING_PREFERENCE_IDS: Array[String] = [
	"fastest",
	"shortest",
	"avoid_small_roads",
	"avoid_major_roads",
]
const ROUTING_PREFERENCE_LABELS: Array[String] = [
	"Fastest",
	"Shortest",
	"Avoid small roads",
	"Avoid major roads",
]

var _status_label: Label
var _preference_select: OptionButton
var _waypoint_list: ItemList
var _remove_waypoint_button: Button
var _clear_waypoints_button: Button

func _ready() -> void:
	_build_ui()

func set_status(text: String) -> void:
	_ensure_ui()
	_status_label.text = text

func set_preference(preference: String) -> void:
	_ensure_ui()
	var index: int = ROUTING_PREFERENCE_IDS.find(preference)
	if index >= 0:
		_preference_select.select(index)

func preference_label(preference: String) -> String:
	var index: int = ROUTING_PREFERENCE_IDS.find(preference)
	return ROUTING_PREFERENCE_LABELS[index] if index >= 0 else preference

func set_waypoints(points: Array) -> void:
	_ensure_ui()
	_waypoint_list.clear()
	for index in range(points.size()):
		var value: Variant = points[index]
		if typeof(value) != TYPE_VECTOR2:
			continue
		var point: Vector2 = value
		_waypoint_list.add_item("%d  %.0f, %.0f" % [index + 1, point.x, point.y])
	_remove_waypoint_button.disabled = points.is_empty()
	_clear_waypoints_button.disabled = points.is_empty()

func _build_ui() -> void:
	if _status_label != null:
		return
	layer = 50
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -520.0
	panel.offset_top = 14.0
	panel.offset_right = -14.0
	panel.offset_bottom = 250.0
	add_child(panel)
	var content := VBoxContainer.new()
	panel.add_child(content)

	_status_label = Label.new()
	_status_label.text = "GPS starting…"
	content.add_child(_status_label)

	_preference_select = OptionButton.new()
	for label_text in ROUTING_PREFERENCE_LABELS:
		_preference_select.add_item(label_text)
	_preference_select.selected = 0
	_preference_select.tooltip_text = "Routing preference used for every GPS leg"
	_preference_select.item_selected.connect(_on_preference_selected)
	content.add_child(_preference_select)

	var help := Label.new()
	help.text = "Shift+click destination · Cmd/Ctrl+Shift+click waypoint"
	content.add_child(help)

	_waypoint_list = ItemList.new()
	_waypoint_list.custom_minimum_size = Vector2(0.0, 80.0)
	_waypoint_list.select_mode = ItemList.SELECT_SINGLE
	content.add_child(_waypoint_list)

	var buttons := HBoxContainer.new()
	content.add_child(buttons)
	_remove_waypoint_button = Button.new()
	_remove_waypoint_button.text = "Remove selected"
	_remove_waypoint_button.pressed.connect(_on_remove_waypoint_pressed)
	buttons.add_child(_remove_waypoint_button)
	_clear_waypoints_button = Button.new()
	_clear_waypoints_button.text = "Clear waypoints"
	_clear_waypoints_button.pressed.connect(_on_clear_waypoints_pressed)
	buttons.add_child(_clear_waypoints_button)
	set_waypoints([])

func _ensure_ui() -> void:
	if _status_label == null:
		_build_ui()

func _on_preference_selected(index: int) -> void:
	if index >= 0 and index < ROUTING_PREFERENCE_IDS.size():
		preference_selected.emit(ROUTING_PREFERENCE_IDS[index])

func _on_remove_waypoint_pressed() -> void:
	var selected: PackedInt32Array = _waypoint_list.get_selected_items()
	if selected.is_empty():
		set_status("Select a waypoint to remove")
		return
	remove_waypoint_requested.emit(int(selected[0]))

func _on_clear_waypoints_pressed() -> void:
	clear_waypoints_requested.emit()
