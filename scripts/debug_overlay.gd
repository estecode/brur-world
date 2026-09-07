extends CanvasLayer

# On-screen runtime/performance readout for validating camera, LOD, rendering and streaming.

@onready var main: Node = get_parent()
@onready var camera_rig: Node = main.get_node("CameraRig")
@onready var camera: Camera3D = camera_rig.get_node("Camera3D") as Camera3D
@onready var label: Label = $Panel/Label

var sample_time: float = 0.0
var frame_count: int = 0
var frame_sum_ms: float = 0.0
var worst_frame_ms: float = 0.0
var shown_avg_ms: float = 0.0
var shown_worst_ms: float = 0.0

func _process(delta: float) -> void:
	var frame_ms: float = delta * 1000.0
	frame_count += 1
	frame_sum_ms += frame_ms
	worst_frame_ms = maxf(worst_frame_ms, frame_ms)
	sample_time += delta
	if sample_time >= 1.0:
		shown_avg_ms = frame_sum_ms / float(maxi(1, frame_count))
		shown_worst_ms = worst_frame_ms
		sample_time = 0.0
		frame_count = 0
		frame_sum_ms = 0.0
		worst_frame_ms = 0.0

	var distance: float = float(camera_rig.call("get_distance"))
	var focus: Vector3 = camera_rig.call("get_focus_world") as Vector3
	var lod: int = int(main.get("current_lod"))
	var loaded_value: Variant = main.get("loaded")
	var loaded_count: int = 0
	if typeof(loaded_value) == TYPE_DICTIONARY:
		loaded_count = (loaded_value as Dictionary).size()
	var cache_value: Variant = main.get("mesh_cache")
	var mesh_cache_count: int = 0
	if typeof(cache_value) == TYPE_DICTIONARY:
		mesh_cache_count = (cache_value as Dictionary).size()
	var min_tile: Vector2i = main.get("last_min_tile") as Vector2i
	var max_tile: Vector2i = main.get("last_max_tile") as Vector2i
	var spacing: float = float(main.get("current_layer_spacing"))
	var ground_hits: PackedVector3Array = camera_rig.call("get_ground_view_corners") as PackedVector3Array

	var poi_count: int = 0
	var poi_cache_count: int = 0
	var poi_layer: Node = main.get_node_or_null("POILayer")
	if poi_layer != null:
		var pois_value: Variant = poi_layer.get("active_pois")
		if typeof(pois_value) == TYPE_ARRAY:
			poi_count = (pois_value as Array).size()
		var poi_cache_value: Variant = poi_layer.get("tile_cache")
		if typeof(poi_cache_value) == TYPE_DICTIONARY:
			poi_cache_count = (poi_cache_value as Dictionary).size()

	var fps: float = Engine.get_frames_per_second()
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objects: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

	label.text = (
		"BRUR WORLD DEBUG\n"
		+ "FPS: %.0f   frame avg: %.2f ms   worst 1s: %.2f ms\n" % [fps, shown_avg_ms, shown_worst_ms]
		+ "draw calls: %d   objects: %d   nodes: %d\n" % [draw_calls, objects, nodes]
		+ "distance: %.0f m   lod: %d   road tiles: %d   road cache: %d\n" % [distance, lod, loaded_count, mesh_cache_count]
		+ "POIs: %d   POI tile cache: %d\n" % [poi_count, poi_cache_count]
		+ "camera near/far: %.1f / %.0f   fov: %.1f\n" % [camera.near, camera.far, camera.fov]
		+ "focus: x %.0f   z %.0f\n" % [focus.x, focus.z]
		+ "visible tiles: %s -> %s\n" % [str(min_tile), str(max_tile)]
		+ "ground corner hits: %d / 4   layer spacing: %.1f m" % [ground_hits.size(), spacing]
	)
