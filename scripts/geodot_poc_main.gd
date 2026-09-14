extends "res://scripts/main.gd"

## POC composition of the normal BRUR game with GeoDot as the road/building presentation path.
## Everything else comes from scenes/main.tscn unchanged.

const LUND_FOCUS := Vector3(-489086.0, 0.0, 1582123.0)
const LUND_ALTITUDE_M := 9000.0

@onready var geodot_world_layer: Node3D = $World/GeoDotWorldLayer
@onready var legacy_building_layer: Node = $BuildingLayer

func _ready() -> void:
	super._ready()
	if legacy_building_layer != null and legacy_building_layer.has_method("set_streaming_enabled"):
		legacy_building_layer.call("set_streaming_enabled", false)
	var gpkg_path := OS.get_environment("BRUR_GEODOT_GPKG")
	if gpkg_path.is_empty():
		push_error("GeoDot POC requires BRUR_GEODOT_GPKG=/absolute/path/to/sweden-brur.gpkg")
		return
	if geodot_world_layer == null or not geodot_world_layer.has_method("setup"):
		push_error("GeoDot POC scene is missing GeoDotWorldLayer")
		return
	var result: Dictionary = geodot_world_layer.call("setup", get_world_coordinates(), camera_rig, gpkg_path)
	if result.get("ok", false) != true:
		push_error("GeoDot POC setup failed: %s" % String(result.get("error", "unknown")))
		return
	print("GeoDot POC dataset: ", result)
	if OS.get_environment("BRUR_GEODOT_KEEP_VIEW") != "1" and camera_rig.has_method("set_view_altitude"):
		camera_rig.call_deferred("set_view_altitude", LUND_FOCUS, LUND_ALTITUDE_M)

func _process(_delta: float) -> void:
	if manifest.is_empty():
		return
	# Keep the ordinary BRUR background/depth layout alive, but intentionally do not
	# schedule or publish the legacy BRS/BRT road presentation in this POC scene.
	_update_depth_layout(false)

func consume_perf_metrics() -> Dictionary:
	var metrics: Dictionary = {}
	if geodot_world_layer != null and geodot_world_layer.has_method("consume_perf_metrics"):
		metrics = geodot_world_layer.call("consume_perf_metrics")
	return {
		"road_build_ms": float(metrics.get("geodot_build_ms", 0.0)),
		"road_build_max_ms": float(metrics.get("geodot_build_max_ms", 0.0)),
		"road_tiles_built": int(metrics.get("geodot_publishes", 0)),
		"road_refresh_ms": float(metrics.get("geodot_query_ms", 0.0)),
		"road_refresh_max_ms": float(metrics.get("geodot_query_max_ms", 0.0)),
		"road_cache_hits": 0,
		"road_cache_misses": int(metrics.get("geodot_queries", 0)),
		"road_pending": int(metrics.get("geodot_pending_cells", 0)),
	}

func geodot_debug_snapshot() -> Dictionary:
	if geodot_world_layer != null and geodot_world_layer.has_method("debug_snapshot"):
		return geodot_world_layer.call("debug_snapshot")
	return {}
