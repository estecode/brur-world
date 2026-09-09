extends SceneTree

## Headless structural tests for persistent overlay layout and collapse/restore behavior.
##
## Dependencies:
## - overlay_layout.gd and overlay_window_header.gd own presentation-only window behavior.
## - scenes/main.tscn supplies production debug, sun/time, and altitude composition.
## - gps_search_ui.gd supplies the production GPS/search presentation composition.

const OverlayLayoutScript = preload("res://scripts/overlay_layout.gd")
const OverlayWindowHeaderScript = preload("res://scripts/overlay_window_header.gd")
const GpsSearchUiScript = preload("res://scripts/gps_search_ui.gd")
const REFERENCE_SIZE := Vector2(1280.0, 720.0)

func _init() -> void:
	_test_production_structure()
	call_deferred("_test_layout_and_collapse")

func _test_production_structure() -> void:
	var packed_scene: PackedScene = load("res://scenes/main.tscn") as PackedScene
	_assert(packed_scene != null, "main scene loads")
	var scene: Node = packed_scene.instantiate()

	var debug_panel: Control = scene.get_node_or_null("DebugOverlay/Panel") as Control
	var debug_header: Button = scene.get_node_or_null("DebugOverlay/WindowHeader") as Button
	_assert(debug_panel != null, "debug panel exists")
	_assert(debug_header != null, "debug panel has a persistent collapse header")
	_assert(str(debug_header.get("title_text")) == "BRUR WORLD DEBUG", "debug header identifies its panel")
	_assert(int(debug_header.get("slot")) == OverlayLayoutScript.Slot.TOP_LEFT, "debug owns the top-left overlay slot")

	var sun_panel: Control = scene.get_node_or_null("DebugOverlay/SunTimeOverride") as Control
	var sun_header: Button = scene.get_node_or_null("DebugOverlay/SunTimeHeader") as Button
	var legacy_toggle: CheckButton = scene.get_node_or_null("DebugOverlay/SunTimeOverride/LegacyLightToggle") as CheckButton
	var sun_controller: Node = scene.get_node_or_null("SunRuntimeController")
	_assert(sun_panel != null, "sun/time controls exist")
	_assert(sun_header != null, "sun/time controls have a persistent collapse header")
	_assert(int(sun_header.get("slot")) == OverlayLayoutScript.Slot.BOTTOM_LEFT, "sun/time owns the bottom-left overlay slot")
	_assert(legacy_toggle != null, "legacy-light control is owned by the sun/time window")
	_assert(sun_controller != null and sun_controller.get("legacy_toggle_path") == NodePath("../DebugOverlay/SunTimeOverride/LegacyLightToggle"), "sun controller still targets the production legacy-light toggle")

	var altitude_panel: Control = scene.get_node_or_null("CameraAltitudeUi/Panel") as Control
	_assert(altitude_panel != null, "camera altitude HUD remains present")
	_assert(is_equal_approx(altitude_panel.anchor_left, 0.5) and is_equal_approx(altitude_panel.anchor_right, 0.5), "compact altitude HUD remains top-centre outside overlay slots")

	var gps_ui: CanvasLayer = CanvasLayer.new()
	gps_ui.set_script(GpsSearchUiScript)
	gps_ui.call("_create_ui")
	var gps_panel: Control = gps_ui.get_node_or_null("Panel") as Control
	var gps_header: Button = gps_ui.get_node_or_null("WindowHeader") as Button
	_assert(gps_panel != null, "GPS/search panel exists")
	_assert(gps_header != null, "GPS/search panel has a persistent collapse header")
	_assert(int(gps_header.get("slot")) == OverlayLayoutScript.Slot.TOP_RIGHT, "GPS/search owns the top-right overlay slot")
	gps_ui.free()
	scene.free()

func _test_layout_and_collapse() -> void:
	var surface: Control = Control.new()
	surface.name = "ReferenceViewport"
	surface.size = REFERENCE_SIZE
	root.add_child(surface)

	var debug_body: PanelContainer = PanelContainer.new()
	debug_body.name = "DebugBody"
	debug_body.custom_minimum_size = Vector2(506.0, 300.0)
	surface.add_child(debug_body)
	var debug_header: Button = _make_header("DebugHeader", "BRUR WORLD DEBUG", "../DebugBody", OverlayLayoutScript.Slot.TOP_LEFT, 506.0)
	surface.add_child(debug_header)

	var gps_body: PanelContainer = PanelContainer.new()
	gps_body.name = "GpsBody"
	gps_body.custom_minimum_size = Vector2(486.0, 270.0)
	surface.add_child(gps_body)
	var gps_header: Button = _make_header("GpsHeader", "GPS / SEARCH", "../GpsBody", OverlayLayoutScript.Slot.TOP_RIGHT, 486.0)
	surface.add_child(gps_header)

	var sun_body: PanelContainer = PanelContainer.new()
	sun_body.name = "SunBody"
	sun_body.custom_minimum_size = Vector2(646.0, 120.0)
	surface.add_child(sun_body)
	var sun_header: Button = _make_header("SunHeader", "SUN / TIME", "../SunBody", OverlayLayoutScript.Slot.BOTTOM_LEFT, 646.0)
	surface.add_child(sun_header)

	await process_frame
	_assert(surface.size == REFERENCE_SIZE, "layout surface uses the project reference viewport size")
	_assert(debug_body.visible and gps_body.visible and sun_body.visible, "all major overlay panels can be visible simultaneously")
	_assert(not debug_body.get_global_rect().intersects(gps_body.get_global_rect()), "default debug and GPS panel rects do not overlap")
	_assert(not debug_body.get_global_rect().intersects(sun_body.get_global_rect()), "default debug and sun/time panel rects do not overlap")
	_assert(not gps_body.get_global_rect().intersects(sun_body.get_global_rect()), "default GPS and sun/time panel rects do not overlap")
	_assert(not debug_header.get_global_rect().intersects(gps_header.get_global_rect()), "top overlay headers do not overlap")
	_assert(not debug_header.get_global_rect().intersects(sun_header.get_global_rect()), "debug and sun/time headers do not overlap")
	_assert(not gps_header.get_global_rect().intersects(sun_header.get_global_rect()), "GPS and sun/time headers do not overlap")

	_assert_collapse_restore(debug_header, debug_body, "debug")
	_assert_collapse_restore(gps_header, gps_body, "GPS")
	_assert_collapse_restore(sun_header, sun_body, "sun/time")

	surface.queue_free()
	print("godot UI overlay tests: OK")
	quit(0)

func _assert_collapse_restore(header: Button, body: Control, description: String) -> void:
	header.call("set_collapsed", true)
	_assert(not body.visible, "%s body collapses" % description)
	_assert(header.visible and bool(header.call("is_collapsed")), "%s header remains available while collapsed" % description)
	header.call("set_collapsed", false)
	_assert(body.visible and not bool(header.call("is_collapsed")), "%s body restores" % description)

func _make_header(node_name: String, title: String, target: String, slot: int, width: float) -> Button:
	var header: Button = Button.new()
	header.name = node_name
	header.set_script(OverlayWindowHeaderScript)
	header.set("target_path", NodePath(target))
	header.set("title_text", title)
	header.set("slot", slot)
	header.set("panel_width", width)
	return header

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("UI overlay test failed: " + message)
	quit(1)
