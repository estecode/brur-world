class_name RoadSpeedLimitQuery
extends RefCounted

## Resolves the nearest explicit OSM speed limit from the existing BRG1/BRS2 routing dataset.
##
## Dependencies:
## - Reads routing.brg and routing_snap.brs only; it does not create a second road graph.
## - Uses the shared WorldCoordinates owner for world-to-projected conversion.
## - Returns unknown for routing fallback speeds so presentation never invents a legal limit.

const GRAPH_MAGIC := "BRG1"
const SNAP_MAGIC := "BRS2"
const GRAPH_HEADER_SIZE := 12
const NODE_RECORD_SIZE := 40
const EDGE_RECORD_SIZE := 34
const SNAP_HEADER_SIZE := 20
const SNAP_CELL_RECORD_SIZE := 16
const SNAP_EDGE_REF_SIZE := 4
const NODE_X_OFFSET := 24
const NODE_Y_OFFSET := 28
const EDGE_SOURCE_OFFSET := 12
const EDGE_TARGET_OFFSET := 16
const EDGE_SPEED_OFFSET := 24
const EDGE_SPEED_SOURCE_OFFSET := 31
const SPEED_SOURCE_OSM := 0
const DEFAULT_MAX_DISTANCE_M := 22.0

var _world_coordinates
var _graph: FileAccess
var _snap: FileAccess
var _node_count: int = 0
var _edge_count: int = 0
var _cell_size_m: float = 0.0
var _cell_count: int = 0
var _ref_count: int = 0
var _cell_table_offset: int = SNAP_HEADER_SIZE
var _ref_table_offset: int = 0

func setup(graph_path: String, snap_path: String, world_coordinates) -> bool:
	_world_coordinates = world_coordinates
	_graph = FileAccess.open(graph_path, FileAccess.READ)
	_snap = FileAccess.open(snap_path, FileAccess.READ)
	if _graph == null or _snap == null:
		_clear_files()
		return false
	if _graph.get_length() < GRAPH_HEADER_SIZE or _snap.get_length() < SNAP_HEADER_SIZE:
		_clear_files()
		return false
	_graph.seek(0)
	if _graph.get_buffer(4).get_string_from_ascii() != GRAPH_MAGIC:
		_clear_files()
		return false
	_node_count = _graph.get_32()
	_edge_count = _graph.get_32()
	_snap.seek(0)
	if _snap.get_buffer(4).get_string_from_ascii() != SNAP_MAGIC:
		_clear_files()
		return false
	_cell_size_m = _snap.get_float()
	_cell_count = _snap.get_32()
	_ref_count = _snap.get_32()
	_snap.get_float() # max legal speed bound; not needed by this read-only query.
	if _cell_size_m <= 0.0 or _cell_count < 0 or _ref_count < 0:
		_clear_files()
		return false
	_ref_table_offset = _cell_table_offset + _cell_count * SNAP_CELL_RECORD_SIZE
	var expected_snap_size := _ref_table_offset + _ref_count * SNAP_EDGE_REF_SIZE
	var expected_graph_size := GRAPH_HEADER_SIZE + _node_count * NODE_RECORD_SIZE + _edge_count * EDGE_RECORD_SIZE
	if _snap.get_length() != expected_snap_size or _graph.get_length() != expected_graph_size:
		_clear_files()
		return false
	return _world_coordinates != null

func is_ready() -> bool:
	return _graph != null and _snap != null and _world_coordinates != null

func speed_limit_kmh_at(world_position: Vector3, max_distance_m: float = DEFAULT_MAX_DISTANCE_M) -> Variant:
	if not is_ready() or not world_position.is_finite():
		return null
	var absolute: Vector2 = _world_coordinates.world_to_absolute(world_position)
	if not absolute.is_finite():
		return null
	var cell := Vector2i(floori(absolute.x / _cell_size_m), floori(absolute.y / _cell_size_m))
	var cell_record := _find_cell(cell.x, cell.y)
	if cell_record.is_empty():
		return null
	var ref_offset := int(cell_record["offset"])
	var ref_count := int(cell_record["count"])
	var best_distance := maxf(0.0, max_distance_m)
	var best_speed: Variant = null
	for item in range(ref_count):
		var ref_position := _ref_table_offset + (ref_offset + item) * SNAP_EDGE_REF_SIZE
		_snap.seek(ref_position)
		var edge_index := _snap.get_32()
		if edge_index < 0 or edge_index >= _edge_count:
			continue
		var edge := _read_edge(edge_index)
		if edge.is_empty() or int(edge["speed_source"]) != SPEED_SOURCE_OSM:
			continue
		var source := _read_node_xy(int(edge["source_index"]))
		var target := _read_node_xy(int(edge["target_index"]))
		if not source.is_finite() or not target.is_finite():
			continue
		var distance := _distance_to_segment(absolute, source, target)
		if distance <= best_distance:
			best_distance = distance
			best_speed = float(edge["speed_kmh"])
	return best_speed

func _find_cell(cx: int, cy: int) -> Dictionary:
	var low := 0
	var high := _cell_count
	while low < high:
		var middle := (low + high) / 2
		var record := _read_cell(middle)
		var record_x := int(record["x"])
		var record_y := int(record["y"])
		if record_x < cx or (record_x == cx and record_y < cy):
			low = middle + 1
		else:
			high = middle
	if low >= _cell_count:
		return {}
	var found := _read_cell(low)
	return found if int(found["x"]) == cx and int(found["y"]) == cy else {}

func _read_cell(index: int) -> Dictionary:
	_snap.seek(_cell_table_offset + index * SNAP_CELL_RECORD_SIZE)
	return {
		"x": _read_signed_32(_snap.get_32()),
		"y": _read_signed_32(_snap.get_32()),
		"offset": _snap.get_32(),
		"count": _snap.get_32(),
	}

func _read_edge(edge_index: int) -> Dictionary:
	var base := GRAPH_HEADER_SIZE + _node_count * NODE_RECORD_SIZE + edge_index * EDGE_RECORD_SIZE
	_graph.seek(base + EDGE_SOURCE_OFFSET)
	var source_index := _graph.get_32()
	var target_index := _graph.get_32()
	_graph.seek(base + EDGE_SPEED_OFFSET)
	var speed_kmh := _graph.get_float()
	_graph.seek(base + EDGE_SPEED_SOURCE_OFFSET)
	var speed_source := _graph.get_8()
	return {
		"source_index": source_index,
		"target_index": target_index,
		"speed_kmh": speed_kmh,
		"speed_source": speed_source,
	}

func _read_node_xy(node_index: int) -> Vector2:
	if node_index < 0 or node_index >= _node_count:
		return Vector2(INF, INF)
	var base := GRAPH_HEADER_SIZE + node_index * NODE_RECORD_SIZE
	_graph.seek(base + NODE_X_OFFSET)
	return Vector2(_graph.get_float(), _graph.get_float())

func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_squared := ab.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(a)
	var fraction := clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
	return point.distance_to(a + ab * fraction)

func _read_signed_32(value: int) -> int:
	return value - 0x100000000 if value >= 0x80000000 else value

func _clear_files() -> void:
	_graph = null
	_snap = null
	_node_count = 0
	_edge_count = 0
	_cell_count = 0
	_ref_count = 0
