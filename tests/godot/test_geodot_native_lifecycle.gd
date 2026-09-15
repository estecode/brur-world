extends SceneTree

const EXTENSION_PATH := "res://addons/geodot/geodot.gdextension"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var gpkg := OS.get_environment("BRUR_GEODOT_GPKG")
	if gpkg.is_empty() or not FileAccess.file_exists(gpkg):
		push_error("BRUR_GEODOT_GPKG fixture missing")
		quit(2)
		return
	var extension := ResourceLoader.load(EXTENSION_PATH)
	if extension == null:
		push_error("GeoDot extension failed to load")
		quit(3)
		return
	var dataset: Variant = load(gpkg)
	if dataset == null or not dataset.has_method("get_feature_layers"):
		push_error("GeoDot dataset failed to load")
		quit(4)
		return
	var layers: Array = dataset.call("get_feature_layers")
	print("GEODOT_NATIVE_LIFECYCLE layers=", layers.size(), " godot=", Engine.get_version_info())
	# Detach every Resource path while GeoDot/GDAL and the GDExtension are alive.
	# The process exit itself is the contract: a post-PASS abort is still failure.
	for value in layers:
		if value is Resource:
			var resource := value as Resource
			if not resource.resource_path.is_empty(): resource.take_over_path("")
	layers.clear()
	if dataset is Resource:
		var dataset_resource := dataset as Resource
		if not dataset_resource.resource_path.is_empty(): dataset_resource.take_over_path("")
	dataset = null
	extension = null
	print("GEODOT_NATIVE_LIFECYCLE=PASS")
	quit(0)
