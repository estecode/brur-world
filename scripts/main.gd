extends Node3D

# Streams portable BRT1 road tiles around the camera and batches each tile into one mesh.

const WORLD_DIR := "res://world_data"
const MAGIC := "BRT1"

@onready var world: Node3D = $World
@onready var camera_rig: Node3D = $CameraRig

var manifest := {}
var tile_size := 32000.0
var origin_x := 0.0
var origin_y := 0.0
var loaded := {}
var current_lod := -1
var last_center := Vector2i(999999, 999999)
var update_accum := 0.0

func _ready() -> void:
	if not _load_manifest():
		push_error("No world_data/manifest.json. Run ./build_sweden.sh first.")
		return
	_create_ground()
	_refresh_tiles(true)

func _process(delta: float) -> void:
	if manifest.is_empty():
		return
	update_accum += delta
	if update_accum < 0.15:
		return
	update_accum = 0.0
	_refresh_tiles(false)

func _load_manifest() -> bool:
	var path := WORLD_DIR + "/manifest.json"
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	manifest = JSON.parse_string(file.get_as_text())
	if typeof(manifest) != TYPE_DICTIONARY:
		return false
	tile_size = float(manifest.get("tile_size", 32000.0))
	origin_x = float(manifest.get("origin_x", 0.0))
	origin_y = float(manifest.get("origin_y", 0.0))
	return true

func _choose_lod(distance: float) -> int:
	if distance > 180000.0:
		return 0
	if distance > 45000.0:
		return 1
	return 2

func _refresh_tiles(force: bool) -> void:
	var focus: Vector3 = camera_rig.get_focus_world()
	var distance: float = camera_rig.get_distance()
	var lod := _choose_lod(distance)
	var abs_x := focus.x + origin_x
	var abs_y := -focus.z + origin_y
	var center := Vector2i(floori(abs_x / tile_size), floori(abs_y / tile_size))
	if not force and lod == current_lod and center == last_center:
		return
	current_lod = lod
	last_center = center

	var radius := clampi(ceili(distance * 0.9 / tile_size) + 2, 2, 28)
	var wanted := {}
	for ty in range(center.y - radius, center.y + radius + 1):
		for tx in range(center.x - radius, center.x + radius + 1):
			var key := "%d:%d:%d" % [lod, tx, ty]
			var path := "%s/lod%d/%d_%d.brtile" % [WORLD_DIR, lod, tx, ty]
			if FileAccess.file_exists(path):
				wanted[key] = true
				if not loaded.has(key):
					var node := _load_tile(path, tx, ty, lod)
					if node:
						world.add_child(node)
						loaded[key] = node

	for key in loaded.keys():
		if not wanted.has(key):
			loaded[key].queue_free()
			loaded.erase(key)

	print("LOD ", lod, " | loaded road tiles: ", loaded.size(), " | center: ", center)

func _load_tile(path: String, tx: int, ty: int, lod: int) -> MeshInstance3D:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 8:
		return null
	var magic := file.get_buffer(4).get_string_from_ascii()
	if magic != MAGIC:
		push_error("Bad tile magic: " + path)
		return null
	var count := file.get_32()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base_widths := [1400.0, 300.0, 20.0]
	for _i in range(count):
		var road_class := file.get_8()
		var x1 := file.get_float()
		var y1 := file.get_float()
		var x2 := file.get_float()
		var y2 := file.get_float()
		var a := Vector3(x1, 10.0, -y1)
		var b := Vector3(x2, 10.0, -y2)
		var d := b - a
		if d.length_squared() < 0.01:
			continue
		var width: float = base_widths[lod] * (1.0 + max(0, 4 - road_class) * 0.10)
		var side := Vector3(-d.z, 0.0, d.x).normalized() * width * 0.5
		st.add_vertex(a - side)
		st.add_vertex(a + side)
		st.add_vertex(b + side)
		st.add_vertex(a - side)
		st.add_vertex(b + side)
		st.add_vertex(b - side)
	var mesh := st.commit()
	if mesh == null:
		return null
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = Vector3(tx * tile_size - origin_x, 0.0, -(ty * tile_size - origin_y))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.95, 0.70)
	instance.material_override = mat
	return instance

func _create_ground() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2200000.0, 2200000.0)
	ground.mesh = plane
	ground.position.y = 0.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.035, 0.045, 0.04)
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ground.material_override = mat
	world.add_child(ground)
