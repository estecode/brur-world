extends CanvasLayer

## Thin offline GPS search presentation.
##
## Dependencies:
## - gps_search_client.gd owns native process/TCP transport.
## - Native BSI2 search owns Sweden-scale matching/ranking.
## - Emits selected projected coordinates only; it does not know routing, waypoints,
##   the player, native routing transport or map rendering.

signal destination_selected(point: Vector2)
signal waypoint_selected(point: Vector2)

const GpsSearchClientScript = preload("res://scripts/gps_search_client.gd")
const RESULT_LIMIT: int = 8

var search_client: Node
var search_field: LineEdit
var result_list: ItemList
var status_label: Label
var destination_button: Button
var waypoint_button: Button
var current_results: Array[Dictionary] = []
var last_search_ms: float = 0.0

func _ready() -> void:
	layer = 45
	_create_ui()
	search_client = GpsSearchClientScript.new()
	search_client.ready_changed.connect(_on_native_ready_changed)
	search_client.response_received.connect(_on_native_response)
	search_client.status_changed.connect(_set_status)
	add_child(search_client)
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
	status_label.text = "Native search starting…"
	content.add_child(status_label)

func _on_native_ready_changed(ready: bool) -> void:
	search_field.editable = ready
	if ready:
		_set_status("Search ready · native offline index")
		if not search_field.text.strip_edges().is_empty():
			search_client.request(search_field.text, RESULT_LIMIT)
	else:
		_set_status("Native search connecting…")

func _on_search_text_changed(query: String) -> void:
	if query.strip_edges().is_empty():
		current_results.clear()
		result_list.clear()
		_set_status("Search offline addresses and POIs")
		_refresh_buttons()
		return
	if search_client == null or not search_client.is_ready():
		_set_status("Native search is not ready yet")
		return
	_set_status("Searching…")
	search_client.request(query, RESULT_LIMIT)

func _on_native_response(query: String, response: Dictionary) -> void:
	if query != search_field.text:
		return
	if not bool(response.get("success", false)):
		current_results.clear()
		result_list.clear()
		_set_status("Search failed: %s" % str(response.get("adapter_error", "unknown")))
		_refresh_buttons()
		return
	last_search_ms = float(response.get("query_ms", 0.0))
	current_results.clear()
	var values: Variant = response.get("results", [])
	if typeof(values) == TYPE_ARRAY:
		for value in values as Array:
			if typeof(value) == TYPE_DICTIONARY:
				current_results.append(value as Dictionary)
	_refresh_result_list()
	_set_status("%d result(s) · native %.2f ms" % [current_results.size(), last_search_ms])

func _refresh_result_list() -> void:
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
