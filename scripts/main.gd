extends Node3D

## Streams portable BRT1 road tiles and renders a configured BRM2 background map.
##
## Dependencies:
## - world_coordinates.gd owns projected/world/tile coordinate conversion.
## - road_lod_policy.gd owns road widths, view-distance LOD, and build budgeting.
## - CameraRig supplies visible world bounds and zoom distance.
## - city_light_renderer.gd consumes authoritative BRM2 urban geometry plus derived runtime POI density.
## - world_data manifest, BRT1 tiles, BRM2 background, and city-light density provide runtime map data.

const WorldCoordinatesScript = preload("res://scripts/world_coordinates.gd")
const RoadLodPolicyScript = preload("res://scripts/road_lod_policy.gd")
const CityLightRendererScript = preload("res://scripts/city_light_renderer.gd")
const WORLD_DIR: String = "res://world_data"
const ROAD_MAGIC: String = "BRT1"
const MAP_MAGIC: String = "BRM2"
const ROAD_MESH_CACHE_LIMIT: int = 512

const MAP_LAND: int = 0
const MAP_FARMLAND: int = 1
const MAP_FOREST: int = 2
const MAP_URBAN: int = 3
const MAP_WATER: int = 4
const BACKGROUND_OCEAN_PRIORITY: int = -6

@export var background_source_path: String = WORLD_DIR + "/background.brmap"

@onready var world: Node3D = $World
@onready var camera_rig: Node3D = $CameraRig
@onready var sun: DirectionalLight3D = $DirectionalLight3D
@onready var world_environment: WorldEnvironment = $WorldEnvironment

var manifest: Dictionary = {}
var tile_size: float = 32000.0
var origin_x: float = 0.0
var origin_y: float = 0.0
var world_coordinates = WorldCoordinatesScript.new(Vector2.ZERO, 32000.0)

var loaded: Dictionary = {}
var mesh_cache: Dictionary = {}
var mesh_cache_order: Array[String] = []
var background_instances: Dictionary = {}
var city_lights: Node3D
var road_material: StandardMaterial3D

var current_lod: int = -1
var last_min_tile: Vector2i = Vector2i(999999, 999999)
var last_max_tile: Vector2i = Vector2i(-999999, -999999)
var current_layer_spacing: float = -1.0
var update_accum: float = 0.0

var pending_tiles: Array[Dictionary] = []
var pending_wanted: Dictionary = {}
var pending_lod: int = -1
var pending_lod_swap: bool = false

var perf_road_build_ms: float = 0.0
var perf_road_build_max_ms: float = 0.0
var perf_road_tiles_built: int = 0
var perf_road_refresh_ms: float = 0.0
var perf_road_refresh_max_ms: float = 0.0
var perf_cache_hits: int = 0
var perf_cache_misses: int = 0

func _ready() -> void:
	if not _load_manifest():
		push_error("No world_data/manifest.json. Run ./build_sweden.sh first.")
		return
	_setup_lighting()
	_setup_road_material()
	_setup_city_lights()
	_create_ground()
	_load_background()
	_update_depth_layout(true)
	_refresh_tiles(true)

func _process(delta: float) -> void:
	if manifest.is_empty():
		return
	_update_depth_layout(false)
	_process_pending_tiles()
	update_accum += delta
	if update_accum < 0.12:
		return
	update_accum = 0.0
	_refresh_tiles(false)

func _load_manifest() -> bool:
	var path: String = WORLD_DIR + "/manifest.json"
	if not FileAccess.file_exists(path):
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	manifest = parsed as Dictionary
	tile_size = float(manifest.get("tile_size", 32000.0))
	origin_x = float(manifest.get("origin_x", 0.0))
	origin_y = float(manifest.get("origin_y", 0.0))
	world_coordinates = WorldCoordinatesScript.new(Vector2(origin_x, origin_y), tile_size)
	return true

func get_world_coordinates():
	return world_coordinates

func set_background_source(path: String) -> void:
	if path.is_empty() or path == background_source_path:
		return
	background_source_path = path
	_clear_background()
	_load_background()
	_update_depth_layout(true)

func _clear_background() -> void:
	for instance_value in background_instances.values():
		var instance: Node = instance_value as Node
		if instance != null:
			instance.queue_free()
	background_instances.clear()

func _setup_lighting() -> void:
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_color = Color(1.0, 0.965, 0.90)
	sun.light_energy = 2.15
	sun.shadow_enabled = false

	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.34, 0.56, 0.76)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.78, 0.86, 0.95)
	environment.ambient_light_energy = 1.05
	world_environment.environment = environment

func _setup_road_material() -> void:
	road_material = StandardMaterial3D.new()
	road_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	road_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	road_material.vertex_color_use_as_albedo = true
	road_material.albedo_color = Color.WHITE

func _setup_city_lights() -> void:
	city_lights = CityLightRendererScript.new()
	city_lights.name = "CityLights"
	city_lights.sun_controller_path = NodePath("../SunRuntimeController")
	city_lights.camera_rig_path = NodePath("../CameraRig")
	add_child(city_lights)

func _choose_lod(distance: float) -> int:
	return RoadLodPolicyScript.choose_lod(distance, current_lod)

func _layer_spacing() -> float:
	return clampf(camera_rig.get_distance() / 6000.0, 4.0, 240.0)

func _background_height(kind: int) -> float:
	# Heights preserve the existing world-space relationship with roads and city
	# lights. Background visual precedence is handled by render priority instead
	# of relying on depth-buffer precision between these nearly coplanar layers.
	match kind:
		MAP_LAND:
			return current_layer_spacing * 1.0
		MAP_WATER:
			return current_layer_spacing * 2.0
		MAP_FARMLAND:
			return current_layer_spacing * 3.0
		MAP_FOREST:
			return current_layer_spacing * 4.0
		MAP_URBAN:
			return current_layer_spacing * 5.0
	return current_layer_spacing

func _background_render_priority(kind: int) -> int:
	match kind:
		MAP_LAND:
			return -5
		MAP_WATER:
			return -4
		MAP_FARMLAND:
			return -3
		MAP_FOREST:
			return -2
		MAP_URBAN:
			return -1
	return -5

func _background_material(kind: int, ocean_base: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.render_priority = BACKGROUND_OCEAN_PRIORITY if ocean_base else _background_render_priority(kind)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = _map_color(kind)
	mat.roughness = 1.0 if ocean_base else 0.95
	return mat

func _road_height() -> float:
	return current_layer_spacing * 6.0

func _update_depth_layout(force: bool) -> void:
	var spacing: float = _layer_spacing()
	if not force and absf(spacing - current_layer_spacing) < 0.25:
		return
	current_layer_spacing = spacing
	for kind_value in background_instances.keys():
		var kind: int = int(kind_value)
		var instance: MeshInstance3D = background_instances[kind] as MeshInstance3D
		if instance != null:
			instance.position.y = _background_height(kind)
	if city_lights != null:
		city_lights.set_base_height(_background_height(MAP_URBAN) + current_layer_spacing * 0.20)
	var road_y: float = _road_height()
	for key in loaded.keys():
		var road_instance: MeshInstance3D = loaded[key] as MeshInstance3D
		if road_instance != null:
			road_instance.position.y = road_y

func _visible_tile_bounds() -> Array[Vector2i]:
	var min_tx: int = 999999
	var min_ty: int = 999999
	var max_tx: int = -999999
	var max_ty: int = -999999
	var points: PackedVector3Array = camera_rig.get_ground_view_corners()
	var focus: Vector3 = camera_rig.get_focus_world()
	points.append(focus)
	for point in points:
		var tile: Vector2i = world_coordinates.world_to_tile(point)
		min_tx = mini(min_tx, tile.x)
		min_ty = mini(min_ty, tile.y)
		max_tx = maxi(max_tx, tile.x)
		max_ty = maxi(max_ty, tile.y)
	var margin: int = 2
	return [Vector2i(min_tx - margin, min_ty - margin), Vector2i(max_tx + margin, max_ty + margin)]

func _refresh_tiles(force: bool) -> void:
	var started_usec: int = Time.get_ticks_usec()
	var distance: float = camera_rig.get_distance()
	var lod: int = _choose_lod(distance)
	var bounds: Array[Vector2i] = _visible_tile_bounds()
	var min_tile: Vector2i = bounds[0]
	var max_tile: Vector2i = bounds[1]
	if not force and lod == pending_lod and min_tile == last_min_tile and max_tile == last_max_tile:
		return

	var lod_changed: bool = lod != current_lod and current_lod >= 0
	pending_lod = lod
	last_min_tile = min_tile
	last_max_tile = max_tile
	pending_lod_swap = lod_changed
	pending_tiles.clear()
	pending_wanted.clear()

	for ty in range(min_tile.y, max_tile.y + 1):
		for tx in range(min_tile.x, max_tile.x + 1):
			var key: String = "%d:%d:%d" % [lod, tx, ty]
			var path: String = "%s/lod%d/%d_%d.brtile" % [WORLD_DIR, lod, tx, ty]
			if not FileAccess.file_exists(path):
				continue
			pending_wanted[key] = true
			if loaded.has(key):
				continue
			pending_tiles.append({"key": key, "path": path, "tx": tx, "ty": ty, "lod": lod})

	if pending_tiles.is_empty():
		_finish_pending_set()
	var elapsed_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
	perf_road_refresh_ms += elapsed_ms
	perf_road_refresh_max_ms = maxf(perf_road_refresh_max_ms, elapsed_ms)

func _process_pending_tiles() -> void:
	var frame_started_usec: int = Time.get_ticks_usec()
	var built_this_frame: int = 0
	while not pending_tiles.is_empty():
		var elapsed_frame_ms: float = float(Time.get_ticks_usec() - frame_started_usec) / 1000.0
		if not RoadLodPolicyScript.can_build_more(elapsed_frame_ms, built_this_frame):
			break
		var item: Dictionary = pending_tiles.pop_front()
		var key: String = String(item["key"])
		if loaded.has(key):
			continue
		var started_usec: int = Time.get_ticks_usec()
		var node: MeshInstance3D = _load_tile(String(item["path"]), int(item["tx"]), int(item["ty"]), int(item["lod"]))
		var elapsed_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
		perf_road_build_ms += elapsed_ms
		perf_road_build_max_ms = maxf(perf_road_build_max_ms, elapsed_ms)
		if node != null:
			node.visible = not pending_lod_swap
			world.add_child(node)
			loaded[key] = node
			perf_road_tiles_built += 1
		built_this_frame += 1
	if pending_tiles.is_empty() and pending_lod >= 0:
		_finish_pending_set()

func _finish_pending_set() -> void:
	if pending_lod_swap:
		for key in pending_wanted.keys():
			if loaded.has(key):
				var new_node: MeshInstance3D = loaded[key] as MeshInstance3D
				if new_node != null:
					new_node.visible = true
	for key in loaded.keys():
		if pending_wanted.has(key):
			continue
		var old_node: Node = loaded[key] as Node
		if old_node != null:
			old_node.queue_free()
		loaded.erase(key)
	current_lod = pending_lod
	pending_lod_swap = false

func _load_tile(path: String, tx: int, ty: int, lod: int) -> MeshInstance3D:
	var mesh: ArrayMesh = null
	if mesh_cache.has(path):
		mesh = mesh_cache[path] as ArrayMesh
		perf_cache_hits += 1
	else:
		perf_cache_misses += 1
		mesh = _build_tile_mesh(path, lod)
		if mesh != null:
			_cache_mesh(path, mesh)
	if mesh == null:
		return null
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = world_coordinates.tile_origin_world(Vector2i(tx, ty), _road_height())
	instance.material_override = road_material
	return instance

func _cache_mesh(path: String, mesh: ArrayMesh) -> void:
	mesh_cache[path] = mesh
	mesh_cache_order.append(path)
	while mesh_cache_order.size() > ROAD_MESH_CACHE_LIMIT:
		var oldest: String = mesh_cache_order.pop_front()
		if mesh_cache.has(oldest):
			mesh_cache.erase(oldest)

func _build_tile_mesh(path: String, _lod: int) -> ArrayMesh:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 8:
		return null
	var magic: String = file.get_buffer(4).get_string_from_ascii()
	if magic != ROAD_MAGIC:
		push_error("Bad tile magic: " + path)
		return null
	var count: int = file.get_32()
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for _i in range(count):
		var road_class: int = file.get_8()
		var x1: float = file.get_float()
		var y1: float = file.get_float()
		var x2: float = file.get_float()
		var y2: float = file.get_float()
		var a: Vector3 = Vector3(x1, 0.0, -y1)
		var b: Vector3 = Vector3(x2, 0.0, -y2)
		var d: Vector3 = b - a
		if d.length_squared() < 0.01:
			continue
		var width: float = RoadLodPolicyScript.road_width_m(road_class)
		var side: Vector3 = Vector3(-d.z, 0.0, d.x).normalized() * width * 0.5
		st.set_color(_road_color(road_class))
		st.add_vertex(a - side)
		st.add_vertex(a + side)
		st.add_vertex(b + side)
		st.add_vertex(a - side)
		st.add_vertex(b + side)
		st.add_vertex(b - side)
	return st.commit()

func consume_perf_metrics() -> Dictionary:
	var result: Dictionary = {
		"road_build_ms": perf_road_build_ms,
		"road_build_max_ms": perf_road_build_max_ms,
		"road_tiles_built": perf_road_tiles_built,
		"road_refresh_ms": perf_road_refresh_ms,
		"road_refresh_max_ms": perf_road_refresh_max_ms,
		"road_cache_hits": perf_cache_hits,
		"road_cache_misses": perf_cache_misses,
		"road_pending": pending_tiles.size(),
	}
	perf_road_build_ms = 0.0
	perf_road_build_max_ms = 0.0
	perf_road_tiles_built = 0
	perf_road_refresh_ms = 0.0
	perf_road_refresh_max_ms = 0.0
	perf_cache_hits = 0
	perf_cache_misses = 0
	return result

func _load_background() -> void:
	var path: String = background_source_path
	if not FileAccess.file_exists(path):
		push_error("Missing BRM2 background: " + path)
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 8:
		return
	var magic: String = file.get_buffer(4).get_string_from_ascii()
	if magic != MAP_MAGIC:
		push_error("Background map is old or invalid. Re-run ./build_sweden.sh.")
		return
	var triangle_count: int = file.get_32()
	var tools: Array[SurfaceTool] = []
	for _kind in range(5):
		var tool: SurfaceTool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools.append(tool)
	if city_lights != null:
		city_lights.begin_urban_data()
	var accepted: int = 0
	for _triangle_index in range(triangle_count):
		var kind: int = file.get_8()
		var p1: Vector3 = world_coordinates.absolute_to_world(Vector2(file.get_float(), file.get_float()))
		var p2: Vector3 = world_coordinates.absolute_to_world(Vector2(file.get_float(), file.get_float()))
		var p3: Vector3 = world_coordinates.absolute_to_world(Vector2(file.get_float(), file.get_float()))
		if kind < 0 or kind >= tools.size():
			continue
		var st: SurfaceTool = tools[kind]
		st.set_normal(Vector3.UP)
		st.add_vertex(p1)
		st.set_normal(Vector3.UP)
		st.add_vertex(p2)
		st.set_normal(Vector3.UP)
		st.add_vertex(p3)
		if kind == MAP_URBAN and city_lights != null:
			city_lights.add_urban_triangle(p1, p2, p3)
		accepted += 1
	for kind in range(tools.size()):
		var mesh: ArrayMesh = tools[kind].commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = _background_material(kind)
		world.add_child(instance)
		background_instances[kind] = instance
		if kind == MAP_URBAN and city_lights != null:
			city_lights.set_urban_mesh(mesh)
	if city_lights != null:
		_load_city_light_poi_density()
		city_lights.finish_urban_data()
	print("Background triangles rendered: ", accepted, " | deterministic compositing enabled")

func _load_city_light_poi_density() -> void:
	var path := WORLD_DIR + "/city_light_density.jsonl"
	if not FileAccess.file_exists(path):
		print("No city_light_density.jsonl yet. Re-run the Sweden build for POI-weighted city lights.")
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var samples := 0
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		var parsed: Variant = JSON.parse_string(line)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var record := parsed as Dictionary
		var count := int(record.get("count", 0))
		if count <= 0:
			continue
		var absolute := Vector2(float(record.get("x", 0.0)), float(record.get("y", 0.0)))
		city_lights.add_poi_density_sample(world_coordinates.absolute_to_world(absolute), count)
		samples += 1
	print("City-light POI density samples loaded: ", samples)

func _map_color(kind: int) -> Color:
	match kind:
		MAP_LAND:
			return Color(0.32, 0.43, 0.27)
		MAP_FARMLAND:
			return Color(0.49, 0.50, 0.28)
		MAP_FOREST:
			return Color(0.16, 0.34, 0.18)
		MAP_URBAN:
			return Color(0.48, 0.45, 0.40)
		MAP_WATER:
			return Color(0.12, 0.31, 0.48)
	return Color(0.3, 0.3, 0.3)

func _road_color(road_class: int) -> Color:
	if road_class <= 0:
		return Color(1.0, 0.58, 0.20)
	if road_class <= 2:
		return Color(1.0, 0.78, 0.36)
	if road_class <= 4:
		return Color(0.92, 0.88, 0.72)
	return Color(0.62, 0.66, 0.64)

func _create_ground() -> void:
	var bounds_value: Variant = manifest.get("bounds", [])
	if typeof(bounds_value) != TYPE_ARRAY:
		return
	var bounds: Array = bounds_value as Array
	if bounds.size() < 4:
		return
	var min_x: float = float(bounds[0])
	var min_y: float = float(bounds[1])
	var max_x: float = float(bounds[2])
	var max_y: float = float(bounds[3])
	var width: float = max_x - min_x
	var depth: float = max_y - min_y
	var margin: float = maxf(80000.0, maxf(width, depth) * 0.12)
	var center_absolute := Vector2((min_x + max_x) * 0.5, (min_y + max_y) * 0.5)
	var center_world: Vector3 = world_coordinates.absolute_to_world(center_absolute)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(width + margin * 2.0, depth + margin * 2.0)
	ground.mesh = plane
	ground.position = center_world
	ground.material_override = _background_material(MAP_WATER, true)
	world.add_child(ground)
