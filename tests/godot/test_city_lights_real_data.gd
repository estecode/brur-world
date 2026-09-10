extends SceneTree

## Verifies production city-light composition against the local authoritative Sweden runtime dataset.
## Dependencies: scenes/main.tscn, ignored world_data including BRM2 + derived POI density, production CityLightRenderer and CameraRig.

const MIN_SWEDEN_SOURCE_CELLS: int = 250
const MIN_POI_DENSITY_CELLS: int = 100
const GRID_SIZE_M: float = 450.0
const MULTIMESH_3D_STRIDE: int = 12

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_assert(FileAccess.file_exists("res://world_data/manifest.json"), "real-data manifest is available")
	_assert(FileAccess.file_exists("res://world_data/background.brmap"), "real-data BRM2 background is available")
	_assert(FileAccess.file_exists("res://world_data/city_light_density.jsonl"), "derived runtime POI density is available")

	var scene := load("res://scenes/main.tscn") as PackedScene
	_assert(scene != null, "production main scene loads")
	if scene == null:
		quit(1)
		return
	var game := scene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	var city_lights := game.get_node_or_null("CityLights")
	var camera_rig := game.get_node_or_null("CameraRig")
	_assert(city_lights != null, "production composition created CityLights")
	_assert(camera_rig != null, "production composition exposes CameraRig")
	if city_lights == null or camera_rig == null:
		game.queue_free()
		await process_frame
		quit(1)
		return

	city_lights.apply_solar_state({"valid": true, "elevation_deg": -8.0})
	camera_rig.set_altitude(5000.0)
	await process_frame

	var stats: Dictionary = city_lights.get_render_stats()
	var source_cells := int(stats.get("source_cell_count", 0))
	var poi_density_cells := int(stats.get("poi_density_cell_count", 0))
	var poi_density_total := int(stats.get("poi_density_total", 0))
	var glow_count := int(stats.get("glow_count", 0))
	var point_count := int(stats.get("point_count", 0))
	var max_glow_count := int(stats.get("max_glow_count", 0))
	var max_point_count := int(stats.get("max_point_count", 0))
	_assert(source_cells >= MIN_SWEDEN_SOURCE_CELLS, "real Sweden urban data produces a substantial source-cell set")
	_assert(poi_density_cells >= MIN_POI_DENSITY_CELLS, "real Sweden runtime POIs produce broad density coverage")
	_assert(poi_density_total > poi_density_cells, "POI density contains real multi-POI activity rather than one marker per cell")
	_assert(glow_count >= mini(source_cells, max_glow_count), "every sampled urban cell keeps baseline glow while POI density may strengthen it")
	_assert(glow_count <= max_glow_count, "overview glow respects its explicit budget")
	_assert(point_count >= mini(source_cells * 4, max_point_count), "local lights keep a baseline urban density before POI weighting")
	_assert(point_count <= max_point_count, "local lights respect their explicit budget")
	_assert(point_count >= 2000, "real Sweden data produces thousands of local emissive lights")
	_assert(bool(stats.get("points_visible", false)), "close real-data view shows local lights")
	_assert(not bool(stats.get("glow_visible", true)), "close real-data view hides overview glow")

	var points := city_lights.get_node_or_null("LocalLightPoints") as MultiMeshInstance3D
	_assert(points != null and points.multimesh != null, "real-data local lights use the production MultiMesh")
	if points != null and points.multimesh != null and points.multimesh.instance_count > 0:
		var point_buffer := points.multimesh.buffer
		_assert(point_buffer.size() == points.multimesh.instance_count * MULTIMESH_3D_STRIDE, "real-data MultiMesh exposes a complete production transform buffer")
		var first_origin := _buffer_origin(point_buffer, 0)
		_assert(point_buffer[0] <= 30.0 and point_buffer[10] <= 30.0, "close real-data light points remain small at ground scale")
		_assert(_has_irregular_cell_offsets(point_buffer, points.multimesh.instance_count), "real-data lights do not collapse onto a visible regular sampling grid")
		_assert(_has_large_geographic_span(point_buffer, points.multimesh.instance_count), "sampled real-data lights span a broad Sweden-sized area")

		camera_rig.set_altitude(170000.0)
		await process_frame
		stats = city_lights.get_render_stats()
		_assert(bool(stats.get("glow_visible", false)) and bool(stats.get("points_visible", false)), "mid-distance real-data view blends overview and local LODs")
		_assert(_buffer_origin(points.multimesh.buffer, 0).is_equal_approx(first_origin), "real-data camera LOD leaves physical light positions unchanged")

		camera_rig.set_altitude(400000.0)
		await process_frame
		stats = city_lights.get_render_stats()
		_assert(bool(stats.get("glow_visible", false)), "far real-data view keeps overview glow")
		_assert(not bool(stats.get("points_visible", true)), "far real-data view hides local points")
		_assert(_buffer_origin(points.multimesh.buffer, 0).is_equal_approx(first_origin), "far real-data LOD still leaves physical light positions unchanged")

	city_lights.apply_solar_state({"valid": true, "elevation_deg": 8.0})
	await process_frame
	stats = city_lights.get_render_stats()
	_assert(not bool(stats.get("glow_visible", true)) and not bool(stats.get("points_visible", true)), "daylight removes real-data nighttime presentation")

	if not _failed:
		print("godot city light real-data tests: OK | source_cells=%d poi_cells=%d pois=%d glow=%d points=%d" % [source_cells, poi_density_cells, poi_density_total, glow_count, point_count])
	game.queue_free()
	await process_frame
	quit(1 if _failed else 0)

func _sample_indices(instance_count: int, requested_count: int) -> Array[int]:
	var result: Array[int] = []
	var sample_count := mini(instance_count, requested_count)
	if sample_count <= 0:
		return result
	if sample_count == 1:
		result.append(0)
		return result
	result.resize(sample_count)
	for sample_index in range(sample_count):
		result[sample_index] = int(round(float(sample_index) * float(instance_count - 1) / float(sample_count - 1)))
	return result

func _buffer_origin(buffer: PackedFloat32Array, index: int) -> Vector3:
	var offset := index * MULTIMESH_3D_STRIDE
	return Vector3(buffer[offset + 3], buffer[offset + 7], buffer[offset + 11])

func _has_irregular_cell_offsets(buffer: PackedFloat32Array, instance_count: int) -> bool:
	var seen: Dictionary = {}
	for index in _sample_indices(instance_count, 2048):
		var origin := _buffer_origin(buffer, index)
		var x_mod := fposmod(origin.x, GRID_SIZE_M)
		var z_mod := fposmod(origin.z, GRID_SIZE_M)
		var key := "%d:%d" % [int(floor(x_mod / 25.0)), int(floor(z_mod / 25.0))]
		seen[key] = true
	if seen.size() < 24:
		print("CITY_LIGHT_DIAG irregular_offset_bucket_count=%d instances=%d" % [seen.size(), instance_count])
	return seen.size() >= 24

func _has_large_geographic_span(buffer: PackedFloat32Array, instance_count: int) -> bool:
	if instance_count < 2:
		return false
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for index in range(instance_count):
		var origin := _buffer_origin(buffer, index)
		min_x = minf(min_x, origin.x)
		max_x = maxf(max_x, origin.x)
		min_z = minf(min_z, origin.z)
		max_z = maxf(max_z, origin.z)
	var span_x := max_x - min_x
	var span_z := max_z - min_z
	if span_x < 100000.0 or span_z < 100000.0:
		print("CITY_LIGHT_DIAG span_x=%.1f span_z=%.1f instances=%d" % [span_x, span_z, instance_count])
	return span_x >= 100000.0 and span_z >= 100000.0

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error("city light real-data test failed: " + message)
