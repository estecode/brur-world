extends Node3D

# Streams portable BRT1 road tiles and renders a triangulated OSM background map.

const WORLD_DIR: String = "res://world_data"
const ROAD_MAGIC: String = "BRT1"
const MAP_MAGIC: String = "BRM2"

const MAP_LAND: int = 0
const MAP_FARMLAND: int = 1
const MAP_FOREST: int = 2
const MAP_URBAN: int = 3
const MAP_WATER: int = 4

@onready var world: Node3D = $World
@onready var camera_rig: Node3D = $CameraRig
@onready var sun: DirectionalLight3D = $DirectionalLight3D
@onready var world_environment: WorldEnvironment = $WorldEnvironment

var manifest: Dictionary = {}
var tile_size: float = 32000.0
var origin_x: float = 0.0
var origin_y: float = 0.0
var loaded: Dictionary = {}
var mesh_cache: Dictionary = {}
var current_lod: int = -1
var last_center: Vector2i = Vector2i(999999, 999999)
var update_accum: float = 0.0

func _ready() -> void:
	if not _load_manifest():
		push_error("No world_data/manifest.json. Run ./build_sweden.sh first.")
		return
	_setup_lighting()
	_create_ground()
	_load_background()
	_refresh_tiles(true)

func _process(delta: float) -> void:
	if manifest.is_empty():
		return
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
	return true

func _setup_lighting() -> void:
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.light_color = Color(1.0, 0.95, 0.84)
	sun.light_energy = 1.35
	sun.shadow_enabled = false

	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.025, 0.04, 0.055)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.68, 0.74, 0.78)
	environment.ambient_light_energy = 0.75
	world_environment.environment = environment

func _choose_lod(distance: float) -> int:
	# Hysteresis prevents rapid LOD bouncing while zoom sits near a threshold.
	if current_lod < 0:
		if distance > 180000.0:
			return 0
		if distance > 45000.0:
			return 1
		return 2

	if current_lod == 0:
		if distance < 155000.0:
			return 1
		return 0

	if current_lod == 1:
		if distance > 205000.0:
			return 0
		if distance < 38000.0:
			return 2
		return 1

	if distance > 56000.0:
		return 1
	return 2

func _refresh_tiles(force: bool) -> void:
	var focus: Vector3 = camera_rig.get_focus_world()
	var distance: float = camera_rig.get_distance()
	var lod: int = _choose_lod(distance)
	var abs_x: float = focus.x + origin_x
	var abs_y: float = -focus.z + origin_y
	var center: Vector2i = Vector2i(floori(abs_x / tile_size), floori(abs_y / tile_size))
	if not force and lod == current_lod and center == last_center:
		return

	var lod_changed: bool = lod != current_lod and current_lod >= 0
	if lod_changed:
		# Never render two road LODs on the same plane in the same frame.
		# Hiding first removes the z-fighting that looked like flashing during zoom.
		for old_key in loaded.keys():
			var old_instance: MeshInstance3D = loaded[old_key] as MeshInstance3D
			if old_instance != null:
				old_instance.visible = false

	current_lod = lod
	last_center = center

	var radius: int = clampi(ceili(distance * 0.9 / tile_size) + 3, 3, 29)
	var wanted: Dictionary = {}
	var new_nodes: Array[MeshInstance3D] = []

	for ty in range(center.y - radius, center.y + radius + 1):
		for tx in range(center.x - radius, center.x + radius + 1):
			var key: String = "%d:%d:%d" % [lod, tx, ty]
			var path: String = "%s/lod%d/%d_%d.brtile" % [WORLD_DIR, lod, tx, ty]
			if not FileAccess.file_exists(path):
				continue
			wanted[key] = true
			if not loaded.has(key):
				var node: MeshInstance3D = _load_tile(path, tx, ty, lod)
				if node != null:
					node.visible = not lod_changed
					world.add_child(node)
					loaded[key] = node
					new_nodes.append(node)

	for key in loaded.keys():
		if not wanted.has(key):
			var old_node: Node = loaded[key] as Node
			if old_node != null:
				old_node.queue_free()
			loaded.erase(key)

	# A LOD swap is now atomic from the renderer's point of view: old level is
	# hidden, new level is fully constructed, then the new level becomes visible.
	if lod_changed:
		for node in new_nodes:
			node.visible = true

	print("LOD ", lod, " | loaded road tiles: ", loaded.size(), " | center: ", center)

func _load_tile(path: String, tx: int, ty: int, lod: int) -> MeshInstance3D:
	var mesh: ArrayMesh = null
	if mesh_cache.has(path):
		mesh = mesh_cache[path] as ArrayMesh
	else:
		mesh = _build_tile_mesh(path, lod)
		if mesh != null:
			mesh_cache[path] = mesh
	if mesh == null:
		return null

	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = Vector3(tx * tile_size - origin_x, 0.0, -(ty * tile_size - origin_y))
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	instance.material_override = mat
	return instance

func _build_tile_mesh(path: String, lod: int) -> ArrayMesh:
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
	var base_widths: Array[float] = [1400.0, 300.0, 20.0]
	for _i in range(count):
		var road_class: int = file.get_8()
		var x1: float = file.get_float()
		var y1: float = file.get_float()
		var x2: float = file.get_float()
		var y2: float = file.get_float()
		var a: Vector3 = Vector3(x1, 10.0, -y1)
		var b: Vector3 = Vector3(x2, 10.0, -y2)
		var d: Vector3 = b - a
		if d.length_squared() < 0.01:
			continue
		var width: float = base_widths[lod] * (1.0 + float(maxi(0, 4 - road_class)) * 0.10)
		var side: Vector3 = Vector3(-d.z, 0.0, d.x).normalized() * width * 0.5
		st.set_color(_road_color(road_class))
		st.add_vertex(a - side)
		st.add_vertex(a + side)
		st.add_vertex(b + side)
		st.add_vertex(a - side)
		st.add_vertex(b + side)
		st.add_vertex(b - side)
	return st.commit()

func _load_background() -> void:
	var path: String = WORLD_DIR + "/background.brmap"
	if not FileAccess.file_exists(path):
		print("No background.brmap yet. Re-run ./build_sweden.sh to build the map background.")
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

	var accepted: int = 0
	for _triangle_index in range(triangle_count):
		var kind: int = file.get_8()
		var x1: float = file.get_float() - origin_x
		var y1: float = file.get_float() - origin_y
		var x2: float = file.get_float() - origin_x
		var y2: float = file.get_float() - origin_y
		var x3: float = file.get_float() - origin_x
		var y3: float = file.get_float() - origin_y
		if kind < 0 or kind >= tools.size():
			continue
		var st: SurfaceTool = tools[kind]
		var height: float = 1.0 + float(kind) * 1.5
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(x1, height, -y1))
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(x2, height, -y2))
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(x3, height, -y3))
		accepted += 1

	for kind in range(tools.size()):
		var mesh: ArrayMesh = tools[kind].commit()
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.mesh = mesh
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = _map_color(kind)
		mat.roughness = 0.95
		instance.material_override = mat
		world.add_child(instance)

	print("Background map triangles rendered: ", accepted, " / ", triangle_count)

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
	var center_x: float = ((min_x + max_x) * 0.5) - origin_x
	var center_y: float = ((min_y + max_y) * 0.5) - origin_y
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(width + margin * 2.0, depth + margin * 2.0)
	ground.mesh = plane
	ground.position = Vector3(center_x, 0.0, -center_y)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.055, 0.16, 0.24)
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ground.material_override = mat
	world.add_child(ground)
