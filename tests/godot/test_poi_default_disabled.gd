extends SceneTree

## Verifies that production map controls start POI presentation disabled.
## Dependencies: production MapControlsUi and a minimal POI presentation API fixture.

const MapControlsUiScript = preload("res://scripts/map_controls_ui.gd")

class FakePoiLayer:
	extends Node
	var presentation_enabled: bool = true

	func set_presentation_enabled(enabled: bool) -> void:
		presentation_enabled = enabled

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var root := Node.new()
	get_root().add_child(root)

	var poi_layer := FakePoiLayer.new()
	poi_layer.name = "PoiLayer"
	root.add_child(poi_layer)

	var controls: CanvasLayer = MapControlsUiScript.new()
	controls.poi_layer_path = NodePath("../PoiLayer")
	root.add_child(controls)

	_assert(not poi_layer.presentation_enabled, "map controls disable POI presentation on startup")
	var panel := controls.get_child(0) as PanelContainer
	var row := panel.get_child(0) as HBoxContainer
	var poi_toggle: CheckButton = null
	for child in row.get_children():
		if child is CheckButton and (child as CheckButton).text == "Show POIs":
			poi_toggle = child as CheckButton
			break
	_assert(poi_toggle != null, "Show POIs control exists")
	_assert(not poi_toggle.button_pressed, "Show POIs control starts unchecked")

	root.free()
	print("godot POI default-disabled test: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("POI default-disabled test failed: " + message)
	quit(1)
