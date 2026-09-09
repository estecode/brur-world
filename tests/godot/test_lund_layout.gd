extends SceneTree

## Headless regression test for the persistent Lund focus control layout.
##
## Dependencies:
## - debug_overlay.gd owns the Lund presentation control.
## - overlay_layout.gd owns the GPS/search top-right window geometry.

const DebugOverlayScript = preload("res://scripts/debug_overlay.gd")
const OverlayLayoutScript = preload("res://scripts/overlay_layout.gd")
const OverlayWindowHeaderScript = preload("res://scripts/overlay_window_header.gd")
const REFERENCE_SIZE := Vector2(1280.0, 720.0)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var surface := Control.new()
	surface.size = REFERENCE_SIZE

	var camera_rig := Node3D.new()
	camera_rig.name = "CameraRig"
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera_rig.add_child(camera)
	surface.add_child(camera_rig)

	var debug_overlay := CanvasLayer.new()
	debug_overlay.name = "DebugOverlay"
	debug_overlay.set_script(DebugOverlayScript)
	var debug_panel := PanelContainer.new()
	debug_panel.name = "Panel"
	debug_panel.position = Vector2(14.0, 52.0)
	debug_panel.size = Vector2(506.0, 280.0)
	var debug_label := Label.new()
	debug_label.name = "Label"
	debug_panel.add_child(debug_label)
	debug_overlay.add_child(debug_panel)
	surface.add_child(debug_overlay)

	root.add_child(surface)
	debug_overlay.set_process(false)
	await process_frame

	var lund_button := debug_overlay.get_node_or_null("LundButton") as Button
	_assert(lund_button != null, "debug overlay exposes exactly one named Lund control")
	_assert(is_equal_approx(lund_button.position.x, debug_panel.position.x), "Lund control stays in the debug overlay's left-owned column")
	_assert(is_equal_approx(lund_button.position.y, debug_panel.position.y + debug_panel.size.y + 6.0), "Lund control follows the debug panel instead of a fixed top-right coordinate")

	var search_panel := PanelContainer.new()
	search_panel.name = "SearchPanel"
	surface.add_child(search_panel)
	var search_header := Button.new()
	search_header.name = "SearchHeader"
	search_header.set_script(OverlayWindowHeaderScript)
	search_header.set("target_path", NodePath("../SearchPanel"))
	search_header.set("title_text", "GPS / SEARCH")
	search_header.set("slot", OverlayLayoutScript.Slot.TOP_RIGHT)
	search_header.set("panel_width", 486.0)
	surface.add_child(search_header)
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
