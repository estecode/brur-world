extends CanvasLayer

# Small on-screen runtime readout for diagnosing camera, LOD, clipping and tile streaming.

@onready var main: Node = get_parent()
@onready var camera_rig: Node = main.get_node("CameraRig")
@onready var camera: Camera3D = camera_rig.get_node("Camera3D") as Camera3D
@onready var label: Label = $Panel/Label

func _process(_delta: float) -> void:
	var distance: float = float(camera_rig.call("get_distance"))
	var focus: Vector3 = camera_rig.call("get_focus_world") as Vector3
	var lod: int = int(main.get("current_lod"))
	var loaded_value: Variant = main.get("loaded")
	var loaded_count: int = 0
	if typeof(loaded_value) == TYPE_DICTIONARY:
		loaded_count = (loaded_value as Dictionary).size()
	var min_tile: Vector2i = main.get("last_min_tile") as Vector2i
	var max_tile: Vector2i = main.get("last_max_tile") as Vector2i
	var spacing: float = float(main.get("current_layer_spacing"))
	var ground_hits: PackedVector3Array = camera_rig.call("get_ground_view_corners") as PackedVector3Array

	label.text = (
		"BRUR WORLD DEBUG\n"
		+ "distance: %.0f m   lod: %d   loaded tiles: %d\n" % [distance, lod, loaded_count]
		+ "camera near/far: %.1f / %.0f   fov: %.1f\n" % [camera.near, camera.far, camera.fov]
		+ "focus: x %.0f   z %.0f\n" % [focus.x, focus.z]
		+ "visible tiles: %s -> %s\n" % [str(min_tile), str(max_tile)]
		+ "ground corner hits: %d / 4   layer spacing: %.1f m" % [ground_hits.size(), spacing]
	)
