class_name GpsSignStyle
extends RefCounted

## Maps navigation road metadata to Swedish-inspired GPS sign presentation.
##
## Dependencies:
## - Consumes plain metadata dictionaries only.
## - Has no routing, SceneTree, transport or rendering dependency.

const MOTORWAY := "motorway"
const MAJOR_ROAD := "major_road"
const LOCAL_ROAD := "local_road"
const SPECIAL_USE := "special_use"

const MOTORWAY_CLASSES: Array[String] = ["motorway", "motorway_link"]
const MAJOR_CLASSES: Array[String] = ["trunk", "trunk_link", "primary", "primary_link", "secondary", "secondary_link", "tertiary", "tertiary_link"]
const SPECIAL_CLASSES: Array[String] = ["cycleway", "path", "footway"]

static func category(metadata: Dictionary) -> String:
	var highway := str(metadata.get("highway", metadata.get("road_class", ""))).strip_edges().to_lower()
	if highway in MOTORWAY_CLASSES:
		return MOTORWAY
	if highway in MAJOR_CLASSES:
		return MAJOR_ROAD
	if highway in SPECIAL_CLASSES:
		return SPECIAL_USE
	return LOCAL_ROAD

static func presentation(metadata: Dictionary) -> Dictionary:
	var style := category(metadata)
	match style:
		MOTORWAY:
			return {"category": style, "background": Color("#16723b"), "foreground": Color.WHITE, "border": Color.WHITE}
		MAJOR_ROAD:
			return {"category": style, "background": Color("#1769aa"), "foreground": Color.WHITE, "border": Color.WHITE}
		SPECIAL_USE:
			return {"category": style, "background": Color("#5f6368"), "foreground": Color.WHITE, "border": Color.WHITE}
		_:
			return {"category": style, "background": Color("#e8edf2"), "foreground": Color("#17202a"), "border": Color("#7b8794")}

static func label(metadata: Dictionary) -> String:
	var route_ref := str(metadata.get("ref", "")).strip_edges()
	var destination_ref := str(metadata.get("destination_ref", metadata.get("destination:ref", ""))).strip_edges()
	var destination := str(metadata.get("destination", "")).strip_edges()
	var name := str(metadata.get("name", "")).strip_edges()
	var exit_ref := str(metadata.get("exit_ref", "")).strip_edges()
	var parts: Array[String] = []
	if not exit_ref.is_empty():
		parts.append("Avfart %s" % exit_ref)
	if not route_ref.is_empty():
		parts.append(route_ref)
	elif not destination_ref.is_empty():
		parts.append(destination_ref)
	if not destination.is_empty():
		parts.append(destination)
	elif not name.is_empty():
		parts.append(name)
	return "  ".join(parts)
