extends SceneTree

## Structural proof that the GeoDot POC is the production BRUR scene plus one presentation child,
## and that renderer selection is an in-place API rather than a gameplay-scene replacement.
const MainScene = preload("res://scenes/main.tscn")
const GeoDotScene = preload("res://scenes/geodot_poc.tscn")
const GeoDotMainScript = preload("res://scripts/geodot_poc_main.gd")
var _failed := false

const SHARED_PATHS := ["World", "CameraRig", "CameraRig/Camera3D", "PoiLayer", "BuildingLayer", "BuildingRuntimeComposition", "GpsRouteLayer", "DriveRenderOriginComposition", "GpsSearchUi", "GpsSearchRouteAdapter", "DriveHud", "DriveHudAdapter", "MapControlsUi", "WorldClockRuntime", "SunRuntimeController", "WorldEnvironment"]

func _init() -> void: call_deferred("_run")

func _run() -> void:
	var legacy := MainScene.instantiate(); var poc := GeoDotScene.instantiate()
	_assert(legacy != null and poc != null, "legacy and GeoDot compositions instantiate")
	if legacy == null or poc == null: quit(1); return
	for path in SHARED_PATHS:
		var legacy_node := legacy.get_node_or_null(path); var poc_node := poc.get_node_or_null(path)
		_assert(legacy_node != null, "production composition contains %s" % path)
		_assert(poc_node != null, "GeoDot composition retains production node %s" % path)
		if legacy_node != null and poc_node != null: _assert(legacy_node.get_class() == poc_node.get_class(), "GeoDot composition preserves node class at %s" % path)
	var geodot_layer := poc.get_node_or_null("World/GeoDotWorldLayer")
	_assert(geodot_layer != null, "GeoDot adds exactly its presentation layer under the shared World")
	_assert(poc.has_method("set_geodot_renderer_enabled"), "POC exposes in-place renderer switching")
	_assert(poc.has_method("is_geodot_active"), "POC exposes current renderer state")
	_test_progressive_activation_contract()
	legacy.free(); poc.free()
	if _failed: quit(1); return
	print("geodot composition contracts: OK"); quit(0)

func _test_progressive_activation_contract() -> void:
	_assert(not GeoDotMainScript.activation_snapshot_ready({"desired_cells": 132, "active_cells": 0}, 9), "activation waits for actual GeoDot geometry")
	_assert(not GeoDotMainScript.activation_snapshot_ready({"desired_cells": 132, "active_cells": 8, "pending_cells": 96}, 9), "activation waits for bounded useful coverage")
	_assert(GeoDotMainScript.activation_snapshot_ready({"desired_cells": 132, "active_cells": 9, "pending_cells": 96}, 9), "large viewport activates after useful coverage while remaining cells stream")
	_assert(GeoDotMainScript.activation_snapshot_ready({"desired_cells": 4, "active_cells": 4, "pending_cells": 0}, 9), "small viewport activates when all desired cells are ready")
	_assert(not GeoDotMainScript.activation_snapshot_ready({"desired_cells": 4, "active_cells": 3, "pending_cells": 1}, 9), "small viewport does not expose incomplete initial coverage")

func _assert(condition: bool, message: String) -> void:
	if condition: return
	_failed = true; push_error("ASSERT FAILED: " + message)
