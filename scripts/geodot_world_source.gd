extends RefCounted
class_name GeoDotWorldSource

## Thin source adapter from GeoDot/GDAL objects into BRUR-owned render records.
##
## Dependencies:
## - Requires the GeoDot GDExtension to register GeoPackage loading before open_dataset().
## - Returns provider-independent dictionaries consumed by BRUR presentation builders.
## - Owns no coordinate conversion, gameplay semantics, camera policy, or rendering nodes.

const BUILDING_LAYER_CANDIDATES := ["buildings", "building", "multipolygons"]
const ROAD_LAYER_CANDIDATES := ["roads", "road", "lines"]

var dataset = null
var building_layer = null
var road_layer = null
var dataset_path := ""
var epsg_code := 0
var feature_layers: Dictionary = {}
var open_ms := 0.0

func open_dataset(path: String) -> Dictionary:
	close()
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"ok": false, "error": "GeoPackage not found: %s" % path}
	var started := Time.get_ticks_usec()
	var loaded: Variant = load(path)
	open_ms = float(Time.get_ticks_usec() - started) / 1000.0
	if loaded == null or not loaded.has_method("get_feature_layers"):
		return {"ok": false, "error": "GeoDot could not load GeoPackage: %s" % path}
	if loaded.has_method("is_valid") and not bool(loaded.call("is_valid")):
		return {"ok": false, "error": "GeoDot returned an invalid GeoPackage dataset"}
	dataset = loaded
	dataset_path = path
	_discover_layers()
	building_layer = _resolve_layer(BUILDING_LAYER_CANDIDATES, "get_outer_vertices")
	road_layer = _resolve_layer(ROAD_LAYER_CANDIDATES, "get_curve3d")
	if building_layer != null and building_layer.has_method("get_epsg_code"):
		epsg_code = int(building_layer.call("get_epsg_code"))
	elif road_layer != null and road_layer.has_method("get_epsg_code"):
		epsg_code = int(road_layer.call("get_epsg_code"))
	return {
		"ok": building_layer != null and road_layer != null,
		"error": "" if building_layer != null and road_layer != null else "Required building/road layers were not found",
		"path": dataset_path,
		"epsg": epsg_code,
		"layers": feature_layers.keys(),
		"building_layer": _layer_name(building_layer),
		"road_layer": _layer_name(road_layer),
		"open_ms": open_ms,
	}

func close() -> void:
	dataset = null
	building_layer = null
	road_layer = null
	dataset_path = ""
	epsg_code = 0
	feature_layers.clear()
	open_ms = 0.0

func is_ready() -> bool:
	return dataset != null and building_layer != null and road_layer != null

func metadata() -> Dictionary:
	return {
		"path": dataset_path,
		"epsg": epsg_code,
		"layers": feature_layers.keys(),
		"building_layer": _layer_name(building_layer),
		"road_layer": _layer_name(road_layer),
		"open_ms": open_ms,
	}

func query_cell(top_left_absolute: Vector2, size_m: float, max_buildings: int, max_roads: int) -> Dictionary:
	if not is_ready():
		return {"ok": false, "error": "GeoDot world source is not ready"}
	var started := Time.get_ticks_usec()
	var raw_buildings: Array = building_layer.call("get_features_in_square", top_left_absolute.x, top_left_absolute.y, size_m, max_buildings)
	var building_query_ms := float(Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	var raw_roads: Array = road_layer.call("get_features_in_square", top_left_absolute.x, top_left_absolute.y, size_m, max_roads)
	var road_query_ms := float(Time.get_ticks_usec() - started) / 1000.0
	var buildings: Array[Dictionary] = []
	for feature in raw_buildings:
		var record := building_record(feature)
		if not record.is_empty():
			buildings.append(record)
	var roads: Array[Dictionary] = []
	for feature in raw_roads:
		var record := road_record(feature)
		if not record.is_empty():
			roads.append(record)
	return {
		"ok": true,
		"buildings": buildings,
		"roads": roads,
		"building_query_ms": building_query_ms,
		"road_query_ms": road_query_ms,
		"building_features": raw_buildings.size(),
		"road_features": raw_roads.size(),
	}

static func building_record(feature: Variant) -> Dictionary:
	if feature == null or not feature.has_method("get_outer_vertices"):
		return {}
	var outer_value: Variant = feature.call("get_outer_vertices")
	if typeof(outer_value) != TYPE_PACKED_VECTOR2_ARRAY:
		return {}
	var outer: PackedVector2Array = outer_value
	if outer.size() < 3:
		return {}
	var ring: Array = []
	var center := Vector2.ZERO
	for point in outer:
		ring.append([point.x, point.y])
		center += point
	center /= float(outer.size())
	var attrs := _feature_attributes(feature)
	return {
		"id": _feature_id(feature),
		"x": center.x,
		"y": center.y,
		"geometry": [{"outer": ring, "holes": []}],
		"tags": _normalized_tags(attrs),
	}

static func road_record(feature: Variant) -> Dictionary:
	if feature == null or not feature.has_method("get_curve3d"):
		return {}
	var curve_value: Variant = feature.call("get_curve3d")
	if curve_value == null or not curve_value.has_method("get_point_count"):
		return {}
	var count := int(curve_value.call("get_point_count"))
	if count < 2:
		return {}
	var points := PackedVector2Array()
	for index in range(count):
		var p: Vector3 = curve_value.call("get_point_position", index)
		points.append(Vector2(p.x, -p.z))
	var attrs := _feature_attributes(feature)
	var tags := _normalized_tags(attrs)
	return {
		"id": _feature_id(feature),
		"points": points,
		"tags": tags,
		"road_class": road_class_from_highway(String(tags.get("highway", ""))),
	}

static func road_class_from_highway(highway: String) -> int:
	match highway.to_lower():
		"motorway", "motorway_link": return 0
		"trunk", "trunk_link": return 1
		"primary", "primary_link": return 2
		"secondary", "secondary_link": return 3
		"tertiary", "tertiary_link": return 4
		_: return 5

func _discover_layers() -> void:
	feature_layers.clear()
	var layers: Array = dataset.call("get_feature_layers")
	for layer in layers:
		var name := _layer_name(layer)
		if not name.is_empty():
			feature_layers[name] = layer

func _resolve_layer(candidates: Array, geometry_method: String) -> Variant:
	for candidate in candidates:
		var wanted := String(candidate).to_lower()
		for key in feature_layers.keys():
			var name := String(key)
			if name.to_lower() == wanted and _layer_supports_geometry(feature_layers[key], geometry_method):
				return feature_layers[key]
	for candidate in candidates:
		var wanted := String(candidate).to_lower()
		for key in feature_layers.keys():
			var name := String(key)
			if wanted in name.to_lower() and _layer_supports_geometry(feature_layers[key], geometry_method):
				return feature_layers[key]
	for key in feature_layers.keys():
		if _layer_supports_geometry(feature_layers[key], geometry_method):
			return feature_layers[key]
	return null

func _layer_supports_geometry(layer: Variant, geometry_method: String) -> bool:
	if layer == null or not layer.has_method("get_all_features"):
		return false
	var sample: Array = layer.call("get_features_near_position", 0.0, 0.0, 1.0, 1) if layer.has_method("get_features_near_position") else []
	if sample.is_empty():
		return true
	return sample[0] != null and sample[0].has_method(geometry_method)

static func _layer_name(layer: Variant) -> String:
	if layer == null:
		return ""
	if layer.has_method("get_file_info"):
		var info: Dictionary = layer.call("get_file_info")
		var name := String(info.get("name", ""))
		if not name.is_empty():
			return name
	var value: Variant = layer.get("name") if layer is Object else null
	return String(value) if value != null else ""

static func _feature_id(feature: Variant) -> String:
	if feature != null and feature.has_method("get_id"):
		return str(feature.call("get_id"))
	return ""

static func _feature_attributes(feature: Variant) -> Dictionary:
	if feature != null and feature.has_method("get_attributes"):
		var value: Variant = feature.call("get_attributes")
		if typeof(value) == TYPE_DICTIONARY:
			return value
	return {}

static func _normalized_tags(attributes: Dictionary) -> Dictionary:
	var tags: Dictionary = {}
	for key in attributes.keys():
		tags[String(key)] = attributes[key]
	for container_key in ["tags", "other_tags"]:
		if not attributes.has(container_key):
			continue
		var raw: Variant = attributes[container_key]
		if typeof(raw) == TYPE_DICTIONARY:
			for key in raw.keys():
				tags[String(key)] = raw[key]
		elif typeof(raw) == TYPE_STRING:
			_merge_tag_string(tags, String(raw))
	return tags

static func _merge_tag_string(tags: Dictionary, raw: String) -> void:
	var text := raw.strip_edges()
	if text.begins_with("{"):
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			for key in parsed.keys():
				tags[String(key)] = parsed[key]
			return
	for pair in text.split(","):
		var parts := String(pair).split("=>", false, 1)
		if parts.size() != 2:
			continue
		var key := String(parts[0]).strip_edges().trim_prefix("\"").trim_suffix("\"")
		var value := String(parts[1]).strip_edges().trim_prefix("\"").trim_suffix("\"")
		if not key.is_empty():
			tags[key] = value
