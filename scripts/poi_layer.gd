extends Node3D

## Streams exported OSM POIs around the camera and renders lightweight map markers.
##
## Dependencies:
## - world_coordinates.gd owns projected/world/tile coordinate conversion.
## - CameraRig supplies visible world bounds and Camera3D supplies hover projection.
## - Presentation visibility affects markers/hover only; searchable POI data is owned elsewhere.

const WorldCoordinatesScript = preload("res://scripts/world_coordinates.gd")
const WORLD_DIR: String = "res://world_data"
const SHOW_DISTANCE: float = 30000.0
const REFRESH_INTERVAL: float = 0.30
const HOVER_INTERVAL: float = 0.10
const HOVER_RADIUS_PX: float = 16.0

@onready var camera_rig: Node3D = get_parent().get_node("CameraRig") as Node3D
@onready var camera: Camera3D = camera_rig.get_node("Camera3D") as Camera3D

var manifest: Dictionary = {}
var tile_size: float = 32000.0
var origin_x: float = 0.0
var origin_y: float = 0.0
var tile_dir: String = "poi_tiles"
var world_coordinates: RefCounted = WorldCoordinatesScript.new(Vector2.ZERO, 32000.0)

var active_pois: Array[Dictionary] = []
var tile_cache: Dictionary = {}
var marker_instance: MultiMeshInstance3D = null
var marker_mesh: BoxMesh = null
var refresh_accum: float = 0.0
var hover_accum: float = 0.0
var last_min_tile: Vector2i = Vector2i(999999, 999999)
var last_max_tile: Vector2i = Vector2i(-999999, -999999)
var last_marker_distance: float = -1.0
var _presentation_enabled: bool = true

var hover_layer: CanvasLayer = null
var hover_panel: PanelContainer = null
var hover_label: Label = null
var hovered_poi: Dictionary = {}

func _ready() -> void:
	_create_hover_ui()
	_load_manifest()
	_refresh(true)

func set_presentation_enabled(enabled: bool) -> void:
	_presentation_enabled = enabled
	if marker_instance != null:
		marker_instance.visible = enabled
	if not enabled:
		_hide_hover()

func is_presentation_enabled() -> bool:
	return _presentation_enabled

func _process(delta: float) -> void:
	if manifest.is_empty():
		return

	var distance: float = float(camera_rig.call("get_distance"))
	_update_marker_scale(distance)

	refresh_accum += delta
	if refresh_accum >= REFRESH_INTERVAL:
		refresh_accum = 0.0
		_refresh(false)

	if _presentation_enabled:
		hover_accum += delta
		if hover_accum >= HOVER_INTERVAL:
			hover_accum = 0.0
			_update_hover()

	if hover_panel != null and hover_panel.visible:
		var pulse: float = 0.88 + 0.12 * sin(float(Time.get_ticks_msec()) * 0.008)
		hover_panel.modulate.a = pulse

func _load_manifest() -> void:
	var path: String = WORLD_DIR + "/manifest.json"
	if not FileAccess.file_exists(path):
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	manifest = parsed as Dictionary
	tile_size = float(manifest.get("tile_size", 32000.0))
	origin_x = float(manifest.get("origin_x", 0.0))
	origin_y = float(manifest.get("origin_y", 0.0))
	world_coordinates = WorldCoordinatesScript.new(Vector2(origin_x, origin_y), tile_size)
	var features_value: Variant = manifest.get("features", {})
	if typeof(features_value) == TYPE_DICTIONARY:
		var features: Dictionary = features_value as Dictionary
		tile_dir = str(features.get("poi_tiles_dir", "poi_tiles"))

func _refresh(force: bool) -> void:
	var distance: float = float(camera_rig.call("get_distance"))
	if distance > SHOW_DISTANCE:
		if not active_pois.is_empty():
			active_pois.clear()
			_rebuild_markers()
		_hide_hover()
		last_min_tile = Vector2i(999999, 999999)
		last_max_tile = Vector2i(-999999, -999999)
		return

	var bounds: Array[Vector2i] = _visible_tile_bounds()
	var min_tile: Vector2i = bounds[0]
	var max_tile: Vector2i = bounds[1]
	if not force and min_tile == last_min_tile and max_tile == last_max_tile:
		return

	last_min_tile = min_tile
	last_max_tile = max_tile
	active_pois.clear()

	for ty in range(min_tile.y, max_tile.y + 1):
		for tx in range(min_tile.x, max_tile.x + 1):
			var tile_pois: Array[Dictionary] = _get_poi_tile(tx, ty)
			active_pois.append_array(tile_pois)

	_rebuild_markers()
	_update_marker_scale(distance, true)
	print("POIs visible: ", active_pois.size(), " | tiles: ", min_tile, " -> ", max_tile, " | cached tiles: ", tile_cache.size())

func _visible_tile_bounds() -> Array[Vector2i]:
	var min_tx: int = 999999
	var min_ty: int = 999999
	var max_tx: int = -999999
	var max_ty: int = -999999
	var points: PackedVector3Array = camera_rig.call("get_ground_view_corners") as PackedVector3Array
	var focus: Vector3 = camera_rig.call("get_focus_world") as Vector3
	points.append(focus)

	for point in points:
		var tile: Vector2i = world_coordinates.call("world_to_tile", point) as Vector2i
		min_tx = mini(min_tx, tile.x)
		min_ty = mini(min_ty, tile.y)
		max_tx = maxi(max_tx, tile.x)
		max_ty = maxi(max_ty, tile.y)

	var margin: int = 1
	return [Vector2i(min_tx - margin, min_ty - margin), Vector2i(max_tx + margin, max_ty + margin)]

func _get_poi_tile(tx: int, ty: int) -> Array[Dictionary]:
	var key: String = "%d:%d" % [tx, ty]
	if tile_cache.has(key):
		return tile_cache[key] as Array[Dictionary]

	var result: Array[Dictionary] = []
	var path: String = "%s/%s/%d_%d.jsonl" % [WORLD_DIR, tile_dir, tx, ty]
	if not FileAccess.file_exists(path):
		tile_cache[key] = result
		return result
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		tile_cache[key] = result
		return result

	while not file.eof_reached():
		var line: String = file.get_line()
		if line.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(line)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var poi: Dictionary = parsed as Dictionary
		if not poi.has("x") or not poi.has("y"):
			continue
		poi["world_position"] = world_coordinates.call(
			"absolute_to_world",
			Vector2(float(poi.get("x", 0.0)), float(poi.get("y", 0.0)))
		) as Vector3
		result.append(poi)

	tile_cache[key] = result
	return result

func _rebuild_markers() -> void:
	if marker_instance != null:
		marker_instance.queue_free()
		marker_instance = null
	marker_mesh = null
	if active_pois.is_empty():
		return

	marker_mesh = BoxMesh.new()
	marker_mesh.size = Vector3(1.0, 1.7, 1.0)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	marker_mesh.material = material

	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = marker_mesh
	multimesh.instance_count = active_pois.size()

	var lift: float = _marker_lift(float(camera_rig.call("get_distance")))
	for i in range(active_pois.size()):
		var poi: Dictionary = active_pois[i]
		var position: Vector3 = _poi_world_position(poi)
		position.y = lift
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, position))
		multimesh.set_instance_color(i, _poi_color(poi))

	marker_instance = MultiMeshInstance3D.new()
	marker_instance.multimesh = multimesh
	marker_instance.visible = _presentation_enabled
	add_child(marker_instance)

func _update_marker_scale(distance: float, force: bool = false) -> void:
	if marker_mesh == null or marker_instance == null:
		return
	if not force and last_marker_distance > 0.0:
		var ratio: float = distance / last_marker_distance
		if ratio > 0.985 and ratio < 1.015:
			return
	last_marker_distance = distance
	var scale_value: float = clampf(distance * 0.0024, 6.0, 58.0)
	marker_mesh.size = Vector3(scale_value, scale_value * 3.06, scale_value)
	marker_instance.position.y = _marker_lift(distance)

func _marker_lift(distance: float) -> float:
	return clampf(distance / 6000.0, 2.0, 20.0) * 8.0

func _poi_world_position(poi: Dictionary) -> Vector3:
	var cached: Variant = poi.get("world_position", Vector3.ZERO)
	if typeof(cached) == TYPE_VECTOR3:
		return cached as Vector3
	return world_coordinates.call(
		"absolute_to_world",
		Vector2(float(poi.get("x", 0.0)), float(poi.get("y", 0.0)))
	) as Vector3

func _update_hover() -> void:
	if not _presentation_enabled or active_pois.is_empty() or camera == null:
		_hide_hover()
		return

	var mouse: Vector2 = get_viewport().get_mouse_position()
	var best_distance: float = HOVER_RADIUS_PX
	var best: Dictionary = {}
	var lift: float = _marker_lift(float(camera_rig.call("get_distance")))

	for poi in active_pois:
		var world_position: Vector3 = _poi_world_position(poi)
		world_position.y = lift
		if camera.is_position_behind(world_position):
			continue
		var screen: Vector2 = camera.unproject_position(world_position)
		var screen_distance: float = screen.distance_to(mouse)
		if screen_distance < best_distance:
			best_distance = screen_distance
			best = poi

	if best.is_empty():
		_hide_hover()
		return

	hovered_poi = best
	hover_label.text = _hover_text(best)
	hover_panel.position = mouse + Vector2(18.0, 18.0)
	hover_panel.visible = true

func _hide_hover() -> void:
	hovered_poi.clear()
	if hover_panel != null:
		hover_panel.visible = false

func _create_hover_ui() -> void:
	hover_layer = CanvasLayer.new()
	hover_layer.layer = 50
	add_child(hover_layer)

	hover_panel = PanelContainer.new()
	hover_panel.visible = false
	hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_panel.custom_minimum_size = Vector2(260.0, 0.0)

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.055, 0.94)
	style.border_color = Color(0.80, 0.95, 1.0, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	hover_panel.add_theme_stylebox_override("panel", style)
	hover_layer.add_child(hover_panel)

	hover_label = Label.new()
	hover_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_label.add_theme_font_size_override("font_size", 15)
	hover_panel.add_child(hover_label)

func _hover_text(poi: Dictionary) -> String:
	var tags_value: Variant = poi.get("tags", {})
	var tags: Dictionary = tags_value as Dictionary if typeof(tags_value) == TYPE_DICTIONARY else {}
	var name: String = str(tags.get("name", "Unnamed POI"))
	var category: String = _poi_category(tags)
	var lines: PackedStringArray = PackedStringArray([name, category])
	var useful_keys: Array[String] = [
		"amenity", "shop", "tourism", "craft", "office", "healthcare",
		"highway", "enforcement", "maxspeed", "surveillance", "camera:type",
		"operator", "opening_hours", "addr:street", "addr:housenumber"
	]
	for key in useful_keys:
		if tags.has(key):
			lines.append("%s: %s" % [key, str(tags[key])])
	lines.append("OSM %s %s" % [str(poi.get("osm_type", "?")), str(poi.get("osm_id", "?"))])
	return "\n".join(lines)

func _poi_category(tags: Dictionary) -> String:
	if str(tags.get("shop", "")) == "hairdresser":
		return "HAIRDRESSER"
	if _is_camera(tags):
		return "CAMERA"
	for key in ["amenity", "shop", "tourism", "craft", "office", "healthcare", "leisure"]:
		if tags.has(key):
			return str(tags[key]).to_upper()
	return "POI"

func _poi_color(poi: Dictionary) -> Color:
	var tags_value: Variant = poi.get("tags", {})
	var tags: Dictionary = tags_value as Dictionary if typeof(tags_value) == TYPE_DICTIONARY else {}
	if _is_camera(tags):
		return Color(1.0, 0.22, 0.18)
	if str(tags.get("shop", "")) == "hairdresser":
		return Color(1.0, 0.25, 0.72)
	var amenity: String = str(tags.get("amenity", ""))
	if amenity in ["police", "fire_station"]:
		return Color(0.25, 0.55, 1.0)
	if amenity in ["hospital", "clinic", "doctors", "pharmacy"] or tags.has("healthcare"):
		return Color(0.25, 1.0, 0.46)
	if amenity in ["fuel", "charging_station"]:
		return Color(1.0, 0.88, 0.18)
	if amenity in ["restaurant", "cafe", "fast_food", "bar", "pub"]:
		return Color(1.0, 0.60, 0.18)
	return Color(0.88, 0.96, 1.0)

func _is_camera(tags: Dictionary) -> bool:
	if str(tags.get("highway", "")) == "speed_camera":
		return true
	if tags.has("enforcement") or tags.has("surveillance"):
		return true
	for key_value in tags.keys():
		if str(key_value).begins_with("camera:"):
			return true
	return false
