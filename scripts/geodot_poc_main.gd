extends "res://scripts/main.gd"

## POC composition of the normal BRUR game with GeoDot as the road/building presentation path.
## Everything else comes from scenes/main.tscn unchanged. Legacy presentation remains active
## until GeoDot setup succeeds, so missing/incompatible optional POC dependencies fail safely.

const LUND_FOCUS := Vector3(-489086.0, 0.0, 1582123.0)
const LUND_ALTITUDE_M := 9000.0

@onready var geodot_world_layer: Node3D = $World/GeoDotWorldLayer
@onready var legacy_building_layer: Node = $BuildingLayer

var _geodot_ready := false
var _geodot_active := false
var _legacy_buildings_enabled_before_geodot := false

func _ready() -> void:
	super._ready()
	var gpkg_path := OS.get_environment("BRUR_GEODOT_GPKG")
	if gpkg_path.is_empty():
		push_warning("GeoDot POC unavailable: BRUR_GEODOT_GPKG is not configured; keeping legacy world presentation")
		return
	if geodot_world_layer == null or not geodot_world_layer.has_method("setup"):
		push_warning("GeoDot POC scene is missing GeoDotWorldLayer; keeping legacy world presentation")
		return
	var result: Dictionary = geodot_world_layer.call("setup", get_world_coordinates(), camera_rig, gpkg_path)
	if result.get("ok", false) != true:
		push_warning("GeoDot POC setup failed: %s; keeping legacy world presentation" % String(result.get("error", "unknown")))
		return
	_geodot_ready = true
	set_geodot_renderer_enabled(true)
	print("GeoDot POC dataset: ", result)
	if OS.get_environment("BRUR_GEODOT_KEEP_VIEW") != "1" and camera_rig.has_method("set_view_altitude"):
		camera_rig.call_deferred("set_view_altitude", LUND_FOCUS, LUND_ALTITUDE_M)

func _process(delta: float) -> void:
	if manifest.is_empty():
		return
	if not _geodot_active:
		super._process(delta)
		return
	# Keep the ordinary BRUR background/depth layout alive, but intentionally do not
	# schedule or publish the legacy BRS/BRT road presentation while GeoDot is active.
	_update_depth_layout(false)

func set_geodot_renderer_enabled(enabled: bool) -> bool:
	if enabled and not _geodot_ready:
		return false
	if enabled == _geodot_active:
		return true
	if enabled:
		_legacy_buildings_enabled_before_geodot = _legacy_buildings_streaming_enabled()
		if legacy_building_layer is Node3D:
			(legacy_building_layer as Node3D).visible = false
		if legacy_building_layer != null and legacy_building_layer.has_method("set_streaming_enabled"):
			legacy_building_layer.call("set_streaming_enabled", false)
		_clear_legacy_roads()
		if geodot_world_layer != null and geodot_world_layer.has_method("set_enabled"):
			geodot_world_layer.call("set_enabled", true)
		_geodot_active = true
		return true

	if geodot_world_layer != null and geodot_world_layer.has_method("set_enabled"):
		geodot_world_layer.call("set_enabled", false)
	_geodot_active = false
	if legacy_building_layer is Node3D:
		(legacy_building_layer as Node3D).visible = true
	if legacy_building_layer != null and legacy_building_layer.has_method("set_streaming_enabled"):
		legacy_building_layer.call("set_streaming_enabled", _legacy_buildings_enabled_before_geodot)
	_refresh_tiles(true)
	return true

func _legacy_buildings_streaming_enabled() -> bool:
	if legacy_building_layer != null and legacy_building_layer.has_method("is_streaming_enabled"):
		return bool(legacy_building_layer.call("is_streaming_enabled"))
	return false

func _clear_legacy_roads() -> void:
	for instance_value in loaded.values():
		var instance := instance_value as Node
		if instance != null:
			instance.queue_free()
	loaded.clear()
	pending_tiles.clear()
	pending_wanted.clear()
	pending_lod = -1
	pending_lod_swap = false
	current_lod = -1
	last_min_tile = Vector2i(999999, 999999)
	last_max_tile = Vector2i(-999999, -999999)

func is_geodot_ready() -> bool:
	return _geodot_ready

func is_geodot_active() -> bool:
	return _geodot_active

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
