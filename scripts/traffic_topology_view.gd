class_name TrafficTopologyView
extends RefCounted

## Read-only traffic view over the authoritative BRG1 routing graph.
## Does not modify, duplicate, or preprocess road topology beyond compact lookup arrays.

const HEADER_SIZE := 12
const NODE_SIZE := 44
const EDGE_SIZE := 32
const MAGIC := "BRG1"

var nodes: Array[Dictionary] = []
var edges: Array[Dictionary] = []
var outgoing_by_node: Dictionary = {}

func load_graph(path: String) -> bool:
	nodes.clear(); edges.clear(); outgoing_by_node.clear()
	if not FileAccess.file_exists(path): return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return false
	if f.get_buffer(4).get_string_from_ascii() != MAGIC: return false
	var node_count := f.get_32()
	var edge_count := f.get_32()
	for i in range(node_count):
		var osm_id := f.get_64()
		var lon := f.get_double()
		var lat := f.get_double()
		var x := f.get_float()
		var y := f.get_float()
		var adjacency_offset := f.get_32()
		var adjacency_count := f.get_32()
		nodes.append({"osm_id": osm_id, "lon": lon, "lat": lat, "x": x, "y": y, "adjacency_offset": adjacency_offset, "adjacency_count": adjacency_count})
	for edge_id in range(edge_count):
		var way_id := f.get_64()
		var segment_index := f.get_32()
		var source_index := f.get_32()
		var target_index := f.get_32()
		var length_m := f.get_float()
		var speed_kmh := f.get_float()
		var road_class := f.get_8()
		var access_class := f.get_8()
		var flags := f.get_8()
		var speed_source := f.get_8()
		var layer_raw := f.get_8()
		var access_reason := f.get_8()
		var layer := layer_raw if layer_raw < 128 else layer_raw - 256
		edges.append({"way_id": way_id, "segment_index": segment_index, "source_index": source_index, "target_index": target_index, "length_m": length_m, "speed_kmh": speed_kmh, "road_class": road_class, "access_class": access_class, "flags": flags, "speed_source": speed_source, "layer": layer, "access_reason": access_reason})
		if not outgoing_by_node.has(source_index): outgoing_by_node[source_index] = []
		(outgoing_by_node[source_index] as Array).append(edge_id)
	return nodes.size() == node_count and edges.size() == edge_count

func has_edge(edge_id: int) -> bool: return edge_id >= 0 and edge_id < edges.size()
func edge_length_m(edge_id: int) -> float: return float(edges[edge_id]["length_m"]) if has_edge(edge_id) else 0.0
func edge_speed_mps(edge_id: int) -> float: return float(edges[edge_id]["speed_kmh"]) / 3.6 if has_edge(edge_id) else 0.0
func edge_heading_rad(edge_id: int) -> float:
	if not has_edge(edge_id): return 0.0
	var e := edges[edge_id]
	var a := nodes[int(e["source_index"])]
	var b := nodes[int(e["target_index"])]
	return atan2(float(b["x"]) - float(a["x"]), float(b["y"]) - float(a["y"]))
func edge_world_position(edge_id: int, fraction: float) -> Vector3:
	if not has_edge(edge_id): return Vector3.INF
	var e := edges[edge_id]
	var a := nodes[int(e["source_index"])]
	var b := nodes[int(e["target_index"])]
	var t := clampf(fraction, 0.0, 1.0)
	return Vector3(lerpf(float(a["x"]), float(b["x"]), t), 0.0, lerpf(float(a["y"]), float(b["y"]), t))
func outgoing_edge_ids(edge_id: int) -> Array:
	if not has_edge(edge_id): return []
	var target := int(edges[edge_id]["target_index"])
	return (outgoing_by_node.get(target, []) as Array).duplicate()
func edge_progress_from_world(edge_id: int, position: Vector3, fallback_progress_m: float) -> float:
	if not has_edge(edge_id): return fallback_progress_m
	var e := edges[edge_id]
	var a := nodes[int(e["source_index"])]
	var b := nodes[int(e["target_index"])]
	var start := Vector2(float(a["x"]), float(a["y"]))
	var finish := Vector2(float(b["x"]), float(b["y"]))
	var delta := finish - start
	var len_sq := delta.length_squared()
	if len_sq <= 0.000001: return fallback_progress_m
	var t := clampf((Vector2(position.x, position.z) - start).dot(delta) / len_sq, 0.0, 1.0)
	return t * edge_length_m(edge_id)
