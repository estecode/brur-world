extends SceneTree

## Headless benchmark for the real offline Sweden GPS search index.
## Dependencies: scripts/gps_search_index.gd and world_data/search_index.jsonl.

const SearchIndexScript = preload("res://scripts/gps_search_index.gd")
const INDEX_PATH: String = "res://world_data/search_index.jsonl"
const QUERIES: Array[String] = [
	"stockholm",
	"lund",
	"storgatan 1",
	"sjukhus",
	"ica",
	"centralstation",
	"malmo",
	"goteborg",
]

func _init() -> void:
	var index = SearchIndexScript.new()
	var started: int = Time.get_ticks_usec()
	var loaded: Dictionary = index.load_file(INDEX_PATH)
	var load_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	if not bool(loaded.get("success", false)):
		push_error("gps search benchmark: failed to load %s: %s" % [INDEX_PATH, str(loaded.get("error", "unknown"))])
		quit(2)
		return

	var timings: Array[float] = []
	print("gps search benchmark | records=%d | load=%.2f ms" % [int(loaded.get("count", 0)), load_ms])
	for query in QUERIES:
		var query_started: int = Time.get_ticks_usec()
		var results: Array[Dictionary] = index.search(query, 8)
		var elapsed_ms: float = float(Time.get_ticks_usec() - query_started) / 1000.0
		timings.append(elapsed_ms)
		var first: String = "-"
		if not results.is_empty():
			first = str(results[0].get("display", ""))
		print("  %-16s %8.2f ms | %d result(s) | first=%s" % [query, elapsed_ms, results.size(), first])

	timings.sort()
	var p50: float = _percentile(timings, 0.50)
	var p95: float = _percentile(timings, 0.95)
	var maximum: float = timings[-1] if not timings.is_empty() else 0.0
	print("gps search benchmark summary | p50=%.2f ms | p95=%.2f ms | max=%.2f ms" % [p50, p95, maximum])
	quit(0)

func _percentile(values: Array[float], fraction: float) -> float:
	if values.is_empty():
		return 0.0
	var index: int = clampi(int(ceil(fraction * float(values.size()))) - 1, 0, values.size() - 1)
	return values[index]
