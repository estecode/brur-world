extends SceneTree

## Headless structural tests for persistent overlay layout and collapse/restore behavior.
##
## Dependencies:
## - overlay_layout.gd and overlay_window_header.gd own presentation-only window behavior.
## - scenes/main.tscn supplies production debug, sun/time, and altitude composition.
## - gps_search_ui.gd and gps_route_ui.gd supply the two production GPS presentation windows.

const OverlayLayoutScript = preload("res://scripts/overlay_layout.gd")
const OverlayWindowHeaderScript = preload("res://scripts/overlay_window_header.gd")
const GpsSearchUiScript = preload("res://scripts/gps_search_ui.gd")
const GpsRouteUiScript = preload("res://scripts/gps_route_ui.gd")
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

	var search_ui: CanvasLayer = CanvasLayer.new()
	search_ui.set_script(GpsSearchUiScript)
	search_ui.call("_create_ui")
	var search_panel: Control = search_ui.get_node_or_null("Panel") as Control
	var search_header: Button = search_ui.get_node_or_null("WindowHeader") as Button
	_assert(search_panel != null, "GPS/search panel exists")
	_assert(search_header != null, "GPS/search panel has a persistent collapse header")
	_assert(int(search_header.get("slot")) == OverlayLayoutScript.Slot.TOP_RIGHT, "GPS/search owns the top-right overlay slot")

	var route_ui: CanvasLayer = CanvasLayer.new()
	route_ui.set_script(GpsRouteUiScript)
	route_ui.call("_build_ui")
	var route_panel: Control = route_ui.get_node_or_null("Panel") as Control
	var route_header: Button = route_ui.get_node_or_null("WindowHeader") as Button
	_assert(route_panel != null, "GPS route/click-waypoint panel exists")
	_assert(route_header != null, "GPS route/click-waypoint panel has a persistent collapse header")
	_assert(str(route_header.get("title_text")) == "GPS / ROUTE", "GPS route header identifies its window")
	_assert(int(route_header.get("slot")) == OverlayLayoutScript.Slot.BOTTOM_RIGHT, "GPS route owns the bottom-right overlay slot")

	search_ui.free()
	route_ui.free()
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

	var search_body: PanelContainer = PanelContainer.new()
	search_body.name = "SearchBody"
	search_body.custom_minimum_size = Vector2(486.0, 270.0)
	surface.add_child(search_body)
	var search_header: Button = _make_header("SearchHeader", "GPS / SEARCH", "../SearchBody", OverlayLayoutScript.Slot.TOP_RIGHT, 486.0)
	surface.add_child(search_header)

	var sun_body: PanelContainer = PanelContainer.new()
	sun_body.name = "SunBody"
	sun_body.custom_minimum_size = Vector2(646.0, 120.0)
	surface.add_child(sun_body)
	var sun_header: Button = _make_header("SunHeader", "SUN / TIME", "../SunBody", OverlayLayoutScript.Slot.BOTTOM_LEFT, 646.0)
	surface.add_child(sun_header)

	var route_body: PanelContainer = PanelContainer.new()
	route_body.name = "RouteBody"
	route_body.custom_minimum_size = Vector2(506.0, 236.0)
	surface.add_child(route_body)
	var route_header: Button = _make_header("RouteHeader", "GPS / ROUTE", "../RouteBody", OverlayLayoutScript.Slot.BOTTOM_RIGHT, 506.0)
	surface.add_child(route_header)

	await process_frame
	_assert(surface.size == REFERENCE_SIZE, "layout surface uses the project reference viewport size")
	_assert(debug_body.visible and search_body.visible and sun_body.visible and route_body.visible, "all persistent overlay panels can be visible simultaneously")
	_assert_no_overlap(debug_body, search_body, "debug and GPS/search bodies")
	_assert_no_overlap(debug_body, sun_body, "debug and sun/time bodies")
	_assert_no_overlap(debug_body, route_body, "debug and GPS/route bodies")
	_assert_no_overlap(search_body, sun_body, "GPS/search and sun/time bodies")
	_assert_no_overlap(search_body, route_body, "GPS/search and GPS/route bodies")
	_assert_no_overlap(sun_body, route_body, "sun/time and GPS/route bodies")
	_assert_no_overlap(debug_header, search_header, "top overlay headers")
	_assert_no_overlap(debug_header, sun_header, "debug and sun/time headers")
	_assert_no_overlap(debug_header, route_header, "debug and GPS/route headers")
	_assert_no_overlap(search_header, sun_header, "GPS/search and sun/time headers")
	_assert_no_overlap(search_header, route_header, "GPS/search and GPS/route headers")
	_assert_no_overlap(sun_header, route_header, "bottom overlay headers")

	_assert_collapse_restore(debug_header, debug_body, "debug")
	_assert_collapse_restore(search_header, search_body, "GPS/search")
	_assert_collapse_restore(sun_header, sun_body, "sun/time")
	_assert_collapse_restore(route_header, route_body, "GPS/route")

	surface.queue_free()
	print("godot UI overlay tests: OK")
	quit(0)

func _assert_no_overlap(first: Control, second: Control, description: String) -> void:
	_assert(not first.get_global_rect().intersects(second.get_global_rect()), "%s do not overlap" % description)

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
