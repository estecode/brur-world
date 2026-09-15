extends RefCounted
class_name GeoDotFarCache

const SCHEMA := 1
var _levels: Array[Dictionary] = []
var _source: Dictionary = {}
var _path := ""

func open(path: String) -> Dictionary:
	close()
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"ok": false, "error": "far cache missing"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "far cache open failed"}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "far cache JSON invalid"}
	var payload: Dictionary = parsed
	if int(payload.get("schema", -1)) != SCHEMA:
		return {"ok": false, "error": "far cache schema mismatch"}
	_source = payload.get("source", {})
	for level_value in payload.get("levels", []):
		if typeof(level_value) != TYPE_DICTIONARY: continue
		var level: Dictionary = level_value
		var index: Dictionary = {}
		for cell_value in level.get("cells", []):
			if typeof(cell_value) != TYPE_ARRAY: continue
			var cell: Array = cell_value
			if cell.size() < 5: continue
			index["%d:%d" % [int(cell[0]), int(cell[1])]] = cell
		_levels.append({"cell_m": float(level.get("cell_m", 1.0)), "index": index})
	_path = path
	return {"ok": not _levels.is_empty(), "levels": _levels.size(), "source": _source}

func close() -> void:
	_levels.clear(); _source.clear(); _path = ""

func level_count() -> int: return _levels.size()
func source_identity() -> Dictionary: return _source.duplicate(true)

func choose_level(min_cell_m: float) -> int:
	if _levels.is_empty(): return -1
	for index in range(_levels.size()):
		if float(_levels[index].cell_m) >= min_cell_m: return index
	return _levels.size() - 1

func query_bounds(bounds: Rect2, level_index: int, max_samples: int, density_scale: float = 1.0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if level_index < 0 or level_index >= _levels.size() or max_samples <= 0: return result
	var level: Dictionary = _levels[level_index]; var cell_m := float(level.cell_m); var index: Dictionary = level.index
	var min_x := floori(bounds.position.x / cell_m); var min_y := floori(bounds.position.y / cell_m)
	var end := bounds.position + bounds.size
	var max_x := floori(end.x / cell_m); var max_y := floori(end.y / cell_m)
	var candidates: Array[Dictionary] = []
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var key := "%d:%d" % [x,y]
			if not index.has(key): continue
			var cell: Array = index[key]
			var coverage := clampf(float(cell[3]) / maxf(1.0, cell_m * cell_m), 0.0, 1.0)
			var weight := coverage * maxf(0.0, density_scale)
			if weight <= 0.0001: continue
			candidates.append({"x":x,"y":y,"cell_m":cell_m,"count":int(cell[2]),"coverage":coverage,"weight":weight,"max_span_m":float(cell[4])})
	# Highest real built coverage wins when the viewport contains more cells than the budget.
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.weight), float(b.weight)): return float(a.weight) > float(b.weight)
		if int(a.y) != int(b.y): return int(a.y) < int(b.y)
		return int(a.x) < int(b.x))
	for index_value in range(mini(max_samples, candidates.size())): result.append(candidates[index_value])
	return result
