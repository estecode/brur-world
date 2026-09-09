extends SceneTree

## Headless regression test for the persistent Lund focus control layout.
##
## Dependencies:
## - debug_overlay.gd owns the Lund presentation control.
## - gps_search_ui.gd and overlay_layout.gd own the GPS/search top-right window.

const DebugOverlayScript = preload("res://scripts/debug_overlay.gd")
const GpsSearchUiScript = preload("res://scripts/gps_search_ui.gd")
const OverlayLayoutScript = preload("res://scripts/overlay_layout.gd")
const REFERENCE_SIZE := Vector2(1280.0, 720.0)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var surface := Control.new()
	surface.size = REFERENCE_SIZE
	root.add_child(surface)

	var debug_overlay := CanvasLayer.new()
	debug_overlay.set_script(DebugOverlayScript)
	surface.add_child(debug_overlay)

	var debug_panel := PanelContainer.new()
	debug_panel.name = "Panel"
	debug_panel.position = Vector2(14.0, 52.0)
	debug_panel.size = Vector2(506.0, 280.0)
	debug_overlay.add_child(debug_panel)
	debug_overlay.call("_create_lund_button")
	debug_overlay.call("_place_lund_button")
	var lund_button := debug_overlay.get_node_or_null("LundButton") as Button
	_assert(lund_button != null, "debug overlay exposes exactly one named Lund control")
	_assert(is_equal_approx(lund_button.position.x, debug_panel.position.x), "Lund control stays in the debug overlay's left-owned column")
	_assert(is_equal_approx(lund_button.position.y, debug_panel.position.y + debug_panel.size.y + 6.0), "Lund control follows the debug panel instead of a fixed top-right coordinate")

	var search_ui := CanvasLayer.new()
	search_ui.set_script(GpsSearchUiScript)
	surface.add_child(search_ui)
	search_ui.call("_create_ui")
	var search_panel := search_ui.get_node_or_null("Panel") as Control
	var search_header := search_ui.get_node_or_null("WindowHeader") as Button
	_assert(search_panel != null and search_header != null, "GPS/search window builds")
	OverlayLayoutScript.apply_window(search_header, search_panel, OverlayLayoutScript.Slot.TOP_RIGHT, 486.0)
	await process_frame
	_assert(not lund_button.get_global_rect().intersects(search_panel.get_global_rect()), "Lund control does not overlap GPS/search body at the reference viewport")
	_assert(not lund_button.get_global_rect().intersects(search_header.get_global_rect()), "Lund control does not overlap GPS/search header at the reference viewport")

	surface.queue_free()
	print("godot Lund layout tests: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("Lund layout test failed: " + message)
	quit(1)
