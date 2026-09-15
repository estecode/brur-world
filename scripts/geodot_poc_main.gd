extends "res://scripts/main.gd"

const TuningPanel = preload("res://scripts/geodot_tuning_panel.gd")
const TuningLogger = preload("res://scripts/geodot_tuning_logger.gd")
const LUND_FOCUS := Vector3(-489086.0, 0.0, 1582123.0)
const LUND_ALTITUDE_M := 9000.0
const MIN_ACTIVATION_CELLS := 9
const FAR_DISABLE_DETAIL_M := 90000.0
const FAR_REENABLE_DETAIL_M := 70000.0
const FORCE_FULL_3D_M := 3000.0

@onready var geodot_world_layer: Node3D = $World/GeoDotWorldLayer
@onready var geodot_far_layer: Node3D = $World/GeoDotFarLayer
@onready var legacy_building_layer: Node = $BuildingLayer

var _geodot_ready := false
var _geodot_active := false
var _geodot_activation_pending := false
var _legacy_buildings_enabled_before_geodot := false
var _detail_streaming_enabled := true
var _tuning_panel: Control = null
var _tuning_logger = TuningLogger.new()
var _tuning: Dictionary = {}

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
	_geodot_ready = true; _geodot_activation_pending = true
	var far_cache := OS.get_environment("BRUR_GEODOT_FAR_CACHE")
	if far_cache.is_empty(): far_cache = ProjectSettings.globalize_path("res://.cache/geodot-far-cache.json")
	if geodot_far_layer != null and geodot_far_layer.has_method("setup"):
		var far_result: Dictionary = geodot_far_layer.call("setup", get_world_coordinates(), camera_rig, far_cache)
		if far_result.get("ok",false) != true: push_warning("GeoDot far cache unavailable: %s" % String(far_result.get("error","unknown")))
	_setup_tuning(result, far_cache)
	_sync_geodot_surface_height()
	print("GeoDot POC dataset: ", result)
	if OS.get_environment("BRUR_GEODOT_KEEP_VIEW") != "1" and camera_rig.has_method("set_view_altitude"):
		camera_rig.call_deferred("set_view_altitude", LUND_FOCUS, LUND_ALTITUDE_M)

func _setup_tuning(source_result: Dictionary, far_cache: String) -> void:
	_tuning_panel = TuningPanel.new(); add_child(_tuning_panel); _tuning = _tuning_panel.call("snapshot")
	_tuning_panel.connect("tuning_changed", Callable(self,"_on_tuning_changed")); _apply_tuning()
	var metadata := {"build": _build_revision(), "godot": Engine.get_version_info(), "source": source_result, "far_cache": far_cache, "os": OS.get_name(), "processor_count": OS.get_processor_count()}
	var log_path := _tuning_logger.open_session(metadata); print("GEODOT_TUNING_LOG=", ProjectSettings.globalize_path(log_path))

func _build_revision() -> String:
	var revision := OS.get_environment("BRUR_BUILD_REVISION")
	return revision if not revision.is_empty() else "unknown"

func _on_tuning_changed(values: Dictionary, key: String, old_value: Variant, new_value: Variant) -> void:
	_tuning = values; _apply_tuning(); _tuning_logger.log_tuning_change(key,old_value,new_value,_tuning)

func _apply_tuning() -> void:
	if geodot_far_layer != null and geodot_far_layer.has_method("set_tuning"): geodot_far_layer.call("set_tuning",_tuning)
	if geodot_world_layer != null:
		geodot_world_layer.set("max_resident_cells", clampi(int(_tuning.get("resident_cells",128)),16,169))

func _process(delta: float) -> void:
	if manifest.is_empty(): return
	_update_distance_policy()
	if _geodot_activation_pending and _geodot_activation_coverage_ready(): _geodot_activation_pending=false; _activate_prepared_geodot()
	if not _geodot_active:
		super._process(delta); _sync_geodot_surface_height(); _log_runtime_sample(); return
	_update_depth_layout(false); _sync_geodot_surface_height(); _log_runtime_sample()

func _camera_distance_to_focus() -> float:
	if camera_rig == null or not camera_rig.has_method("get_focus_world") or get_viewport() == null: return 0.0
	var camera := get_viewport().get_camera_3d()
	if camera == null: return 0.0
	return camera.global_position.distance_to(camera_rig.call("get_focus_world"))

func _update_distance_policy() -> void:
	if not _geodot_ready: return
	var distance := _camera_distance_to_focus()
	# Full 3D is guaranteed around the player; screen-space policy remains free to
	# retain conspicuous/tall buildings farther out.
	geodot_world_layer.set("far_exit_pixels", -1.0 if distance <= FORCE_FULL_3D_M else 2.25)
	if _detail_streaming_enabled and distance >= FAR_DISABLE_DETAIL_M:
		_detail_streaming_enabled=false; geodot_world_layer.call("set_enabled",false)
	elif not _detail_streaming_enabled and distance <= FAR_REENABLE_DETAIL_M:
		_detail_streaming_enabled=true; geodot_world_layer.call("set_enabled",true)

func _log_runtime_sample() -> void:
	if _tuning.is_empty(): return
	var snapshot := geodot_debug_snapshot(); snapshot["camera_distance_m"]=_camera_distance_to_focus(); snapshot["fps"]=Performance.get_monitor(Performance.TIME_FPS); snapshot["objects"]=Performance.get_monitor(Performance.OBJECT_COUNT); snapshot["static_memory_bytes"]=Performance.get_monitor(Performance.MEMORY_STATIC)
	_tuning_logger.sample(snapshot,_tuning)

func _geodot_activation_coverage_ready() -> bool:
	if geodot_world_layer == null or not geodot_world_layer.has_method("debug_snapshot"): return false
	return activation_snapshot_ready(geodot_world_layer.call("debug_snapshot"), MIN_ACTIVATION_CELLS)

static func activation_snapshot_ready(snapshot: Dictionary, minimum_cells: int = MIN_ACTIVATION_CELLS) -> bool:
	var desired := int(snapshot.get("desired_cells", 0)); var active := int(snapshot.get("active_cells", 0))
	if desired <= 0 or active <= 0: return false
	return active >= mini(desired, maxi(1, minimum_cells))

func _activate_prepared_geodot() -> void:
	if not _geodot_ready or _geodot_active: return
	_legacy_buildings_enabled_before_geodot = _legacy_buildings_streaming_enabled()
	if legacy_building_layer is Node3D: (legacy_building_layer as Node3D).visible = false
	if legacy_building_layer != null and legacy_building_layer.has_method("set_streaming_enabled"): legacy_building_layer.call("set_streaming_enabled", false)
	_clear_legacy_presentation(); _sync_geodot_surface_height(); _geodot_active = true
	print("GEODOT_RENDERER_READY coverage_progressive=true legacy_presentation=false")

func set_geodot_renderer_enabled(enabled: bool) -> bool:
	if enabled and not _geodot_ready: return false
	if enabled:
		if _geodot_active: return true
		if geodot_world_layer != null and geodot_world_layer.has_method("set_enabled"): geodot_world_layer.call("set_enabled", true)
		if _geodot_activation_coverage_ready(): _geodot_activation_pending=false; _activate_prepared_geodot()
		else: _geodot_activation_pending=true
		return true
	_geodot_activation_pending=false
	if geodot_world_layer != null and geodot_world_layer.has_method("set_enabled"): geodot_world_layer.call("set_enabled",false)
	if not _geodot_active: return true
	_geodot_active=false
	if legacy_building_layer is Node3D: (legacy_building_layer as Node3D).visible=true
	if legacy_building_layer != null and legacy_building_layer.has_method("set_streaming_enabled"): legacy_building_layer.call("set_streaming_enabled",_legacy_buildings_enabled_before_geodot)
	_refresh_tiles(true); return true

func _sync_geodot_surface_height() -> void:
	if geodot_world_layer != null: geodot_world_layer.position.y=get_road_surface_height()
	if geodot_far_layer != null: geodot_far_layer.position.y=get_road_surface_height()

func _legacy_buildings_streaming_enabled() -> bool:
	if legacy_building_layer != null and legacy_building_layer.has_method("is_streaming_enabled"): return bool(legacy_building_layer.call("is_streaming_enabled"))
	return false

func _clear_legacy_presentation() -> void:
	for instance_value in loaded.values():
		var instance := instance_value as Node
		if instance != null: instance.queue_free()
	loaded.clear(); mesh_cache.clear(); mesh_cache_order.clear(); pending_tiles.clear(); pending_wanted.clear(); pending_lod=-1; pending_lod_swap=false; current_lod=-1
	last_min_tile=Vector2i(999999,999999); last_max_tile=Vector2i(-999999,-999999)

func is_geodot_ready() -> bool: return _geodot_ready
func is_geodot_active() -> bool: return _geodot_active
func consume_perf_metrics() -> Dictionary:
	if geodot_world_layer != null and geodot_world_layer.has_method("consume_perf_metrics"): return geodot_world_layer.call("consume_perf_metrics")
	return {}
func geodot_debug_snapshot() -> Dictionary:
	var snapshot: Dictionary = geodot_world_layer.call("debug_snapshot") if geodot_world_layer != null and geodot_world_layer.has_method("debug_snapshot") else {}
	if geodot_far_layer != null and geodot_far_layer.has_method("debug_snapshot"): snapshot["far"] = geodot_far_layer.call("debug_snapshot")
	if not _tuning.is_empty(): snapshot["tuning"]=_tuning
	return snapshot

func _exit_tree() -> void:
	_tuning_logger.close_session()
	if geodot_far_layer != null and geodot_far_layer.has_method("shutdown"): geodot_far_layer.call("shutdown")
