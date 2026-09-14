extends SceneTree

## Structural proof that the GeoDot POC is the production BRUR scene plus one presentation child,
## and that renderer selection is an in-place API rather than a gameplay-scene replacement.
const MainScene = preload("res://scenes/main.tscn")
const GeoDotScene = preload("res://scenes/geodot_poc.tscn")
var _failed := false

const SHARED_PATHS := [
	"World",
	"CameraRig",
	"CameraRig/Camera3D",
	"PoiLayer",
	"BuildingLayer",
	"BuildingRuntimeComposition",
	"GpsRouteLayer",
	"DriveRenderOriginComposition",
	"GpsSearchUi",
	"GpsSearchRouteAdapter",
	"DriveHud",
	"DriveHudAdapter",
	"MapControlsUi",
	"WorldClockRuntime",
	"SunRuntimeController",
	"WorldEnvironment",
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var legacy := MainScene.instantiate()
	var poc := GeoDotScene.instantiate()
	_assert(legacy != null and poc != null, "legacy and GeoDot compositions instantiate")
	if legacy == null or poc == null:
		quit(1)
		return
	for path in SHARED_PATHS:
		var legacy_node := legacy.get_node_or_null(path)
		var poc_node := poc.get_node_or_null(path)
		_assert(legacy_node != null, "production composition contains %s" % path)
		_assert(poc_node != null, "GeoDot composition retains production node %s" % path)
		if legacy_node != null and poc_node != null:
			_assert(legacy_node.get_class() == poc_node.get_class(), "GeoDot composition preserves node class at %s" % path)
	var geodot_layer := poc.get_node_or_null("World/GeoDotWorldLayer")
	_assert(geodot_layer != null, "GeoDot adds exactly its presentation layer under the shared World")
	_assert(poc.has_method("set_geodot_renderer_enabled"), "POC exposes in-place renderer switching")
	_assert(poc.has_method("is_geodot_active"), "POC exposes current renderer state")
	_assert(poc.get_node_or_null("GpsRouteLayer") == poc.get_node_or_null("GpsRouteLayer"), "renderer switch owns no alternate GPS node")
	legacy.free()
	poc.free()
	if _failed:
		quit(1)
		return
	print("geodot composition contracts: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("ASSERT FAILED: " + message)
