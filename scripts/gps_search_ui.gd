extends CanvasLayer

## Thin offline GPS search presentation.
##
## Dependencies:
## - gps_search_index.gd owns loading, normalization, ranking and result data.
## - Emits selected projected coordinates only; it does not know routing, waypoints,
##   the player, native GPS transport or map rendering.

signal destination_selected(point: Vector2)
signal waypoint_selected(point: Vector2)

const GpsSearchIndexScript = preload("res://scripts/gps_search_index.gd")
const SEARCH_INDEX_PATH: String = "res://world_data/search_index.jsonl"
const RESULT_LIMIT: int = 8

var search_index = GpsSearchIndexScript.new()
var search_field: LineEdit
var result_list: ItemList
var status_label: Label
var destination_button: Button
var waypoint_button: Button
var current_results: Array[Dictionary] = []

func _ready() -> void:
	layer = 45
	_create_ui()
	var loaded: Dictionary = search_index.load_file(SEARCH_INDEX_PATH)
	if bool(loaded.get("success", false)):
		_set_status("Search ready · %d offline places" % int(loaded.get("count", 0)))
	else:
		_set_status("Search index missing — build world_data/search_index.jsonl")
		search_field.editable = false
	_refresh_buttons()

func _create_ui() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 14.0
	panel.offset_top = 330.0
	panel.offset_right = 500.0
	panel.offset_bottom = 600.0
	add_child(panel)

	var content: VBoxContainer = VBoxContainer.new()
	panel.add_child(content)

	var title: Label = Label.new()
	title.text = "Offline GPS search"
	content.add_child(title)

	search_field = LineEdit.new()
	search_field.placeholder_text = "Address or POI…"
	search_field.clear_button_enabled = true
	search_field.text_changed.connect(_on_search_text_changed)
	search_field.text_submitted.connect(_on_search_submitted)
	content.add_child(search_field)

	result_list = ItemList.new()
	result_list.custom_minimum_size = Vector2(0.0, 145.0)
	result_list.select_mode = ItemList.SELECT_SINGLE
	result_list.item_selected.connect(_on_result_selected)
	result_list.item_activated.connect(_on_result_activated)
	content.add_child(result_list)

	var buttons: HBoxContainer = HBoxContainer.new()
	content.add_child(buttons)

	destination_button = Button.new()
	destination_button.text = "Route to"
	destination_button.pressed.connect(_emit_destination)
	buttons.add_child(destination_button)

	waypoint_button = Button.new()
	waypoint_button.text = "Add waypoint"
	waypoint_button.pressed.connect(_emit_waypoint)
	buttons.add_child(waypoint_button)

	status_label = Label.new()
	status_label.text = "Loading search…"
	content.add_child(status_label)

func _on_search_text_changed(query: String) -> void:
	current_results = search_index.search(query, RESULT_LIMIT)
	result_list.clear()
	for result in current_results:
		var display: String = str(result.get("display", ""))
		var subtitle: String = str(result.get("subtitle", ""))
		var kind: String = str(result.get("kind", ""))
		var text: String = display
		if not subtitle.is_empty():
			text += " — " + subtitle
		if not kind.is_empty():
			text += "  [%s]" % kind
		result_list.add_item(text)
	if not current_results.is_empty():
		result_list.select(0)
	_set_status("%d result(s)" % current_results.size() if not query.strip_edges().is_empty() else "Search offline addresses and POIs")
	_refresh_buttons()

func _on_search_submitted(_query: String) -> void:
	if current_results.is_empty():
		return
	_emit_destination()

func _on_result_selected(_index: int) -> void:
	_refresh_buttons()

func _on_result_activated(_index: int) -> void:
	_emit_destination()

func _selected_result() -> Dictionary:
	if result_list == null:
		return {}
	var selected: PackedInt32Array = result_list.get_selected_items()
	if selected.is_empty():
		return {}
	var index: int = int(selected[0])
	if index < 0 or index >= current_results.size():
		return {}
	return current_results[index]

func _selected_point() -> Vector2:
	var result: Dictionary = _selected_result()
	if result.is_empty():
		return Vector2(INF, INF)
	return Vector2(float(result.get("x", INF)), float(result.get("y", INF)))

func _emit_destination() -> void:
	var point: Vector2 = _selected_point()
	if not point.is_finite():
		return
	destination_selected.emit(point)
	_set_status("Destination selected: %s" % str(_selected_result().get("display", "")))

func _emit_waypoint() -> void:
	var point: Vector2 = _selected_point()
	if not point.is_finite():
		return
	waypoint_selected.emit(point)
	_set_status("Waypoint selected: %s" % str(_selected_result().get("display", "")))

func _refresh_buttons() -> void:
	var has_selection: bool = not _selected_result().is_empty()
	if destination_button != null:
		destination_button.disabled = not has_selection
	if waypoint_button != null:
		waypoint_button.disabled = not has_selection

func _set_status(text: String) -> void:
	if status_label != null:
		status_label.text = text
