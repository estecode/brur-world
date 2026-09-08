extends SceneTree

## Headless deterministic and structural tests for lightweight world-scale clouds.
## Dependencies: cloud_field_model.gd and cloud_field_renderer.gd production code.

const CloudFieldModelScript = preload("res://scripts/cloud_field_model.gd")
const CloudFieldRendererScript = preload("res://scripts/cloud_field_renderer.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var model = CloudFieldModelScript.new()
	_test_model_determinism(model)
	_test_profile_bounds_and_weighting(model)
	_test_world_space_motion(model)
	_test_invalid_coverage(model)
	await _test_renderer_structure()
	print("godot cloud field tests: OK")
	quit(0)

func _test_model_determinism(model) -> void:
	var first: Array[Dictionary] = model.generate_cell(Vector2i(3, -2), 0.64, 12345)
	var second: Array[Dictionary] = model.generate_cell(Vector2i(3, -2), 0.64, 12345)
	_assert(first.size() == second.size(), "same seed/config produces same cloud count")
	for index in range(first.size()):
		var first_position: Vector3 = first[index]["position"]
		var second_position: Vector3 = second[index]["position"]
		var first_velocity: Vector3 = first[index]["velocity_mps"]
		var second_velocity: Vector3 = second[index]["velocity_mps"]
		_assert(first[index]["profile"] == second[index]["profile"], "profile generation is deterministic")
		_assert(first_position.is_equal_approx(second_position), "position generation is deterministic")
		_assert(is_equal_approx(float(first[index]["size_m"]), float(second[index]["size_m"])), "size generation is deterministic")
		_assert(first_velocity.is_equal_approx(second_velocity), "wind generation is deterministic")

func _test_profile_bounds_and_weighting(model) -> void:
	var small_count: int = 0
	var large_count: int = 0
	for y in range(-8, 9):
		for x in range(-8, 9):
			var clouds: Array[Dictionary] = model.generate_cell(Vector2i(x, y), 0.78, 9981)
			for cloud in clouds:
				var bounds: Dictionary = model.profile_bounds(String(cloud["profile"]))
				var size_m: float = float(cloud["size_m"])
				var thickness_m: float = float(cloud["thickness_m"])
				var altitude_m: float = float(cloud["altitude_m_asl"])
				var velocity: Vector3 = cloud["velocity_mps"]
				var speed_mps: float = velocity.length()
				_assert(size_m >= float(bounds["size_min_m"]) and size_m <= float(bounds["size_max_m"]), "cloud size stays inside profile bounds")
				_assert(thickness_m >= float(bounds["thickness_min_m"]) and thickness_m <= float(bounds["thickness_max_m"]), "cloud thickness stays inside profile bounds")
				_assert(altitude_m >= float(bounds["altitude_min_m_asl"]) and altitude_m <= float(bounds["altitude_max_m_asl"]), "cloud altitude stays inside profile bounds")
				_assert(speed_mps >= float(bounds["speed_min_mps"]) - 0.001 and speed_mps <= float(bounds["speed_max_mps"]) + 0.001, "cloud speed stays inside profile bounds")
				if String(cloud["profile"]) == "small_cumulus":
					small_count += 1
				else:
					large_count += 1
	_assert(small_count > large_count, "weighted distribution prefers small/medium clouds")
	_assert(large_count > 0, "weighted distribution still includes larger formations")

func _test_world_space_motion(model) -> void:
	var cloud: Dictionary = {}
	for cell_x in range(0, 20):
		var generated: Array[Dictionary] = model.generate_cell(Vector2i(cell_x, 0), 0.8, 771)
		if not generated.is_empty():
			cloud = generated[0]
			break
	_assert(not cloud.is_empty(), "motion fixture generates a cloud")
	var seconds: float = 37.5
	var base: Vector3 = cloud["position"]
	var velocity: Vector3 = cloud["velocity_mps"]
	var moved: Vector3 = model.position_at(cloud, seconds)
	_assert(moved.is_equal_approx(base + velocity * seconds), "movement distance equals velocity times simulation time")

func _test_invalid_coverage(model) -> void:
	_assert(model.generate_cell(Vector2i.ZERO, -5.0, 1).is_empty(), "negative coverage clamps to zero")
	var clamped: Array[Dictionary] = model.generate_cell(Vector2i(2, 2), 4.0, 99)
	var full: Array[Dictionary] = model.generate_cell(Vector2i(2, 2), 1.0, 99)
	_assert(clamped.size() == full.size(), "coverage above one clamps deterministically")

func _test_renderer_structure() -> void:
	var renderer = CloudFieldRendererScript.new()
	root.add_child(renderer)
	await process_frame
	renderer.set_view_state(Vector3.ZERO, 800000.0)
	renderer.set_simulation_seconds(0.0)
	await process_frame

	var stats: Dictionary = renderer.get_render_stats()
	_assert(int(stats["cloud_count"]) > 0, "reference full-zoom view generates clouds")
	_assert(int(stats["puff_instance_count"]) > 0, "renderer creates puff instances")
	_assert(int(stats["puff_instance_count"]) <= int(stats["max_puff_instances"]), "renderer respects explicit instance budget")
	_assert(renderer.multimesh != null and renderer.multimesh.instance_count == int(stats["puff_instance_count"]), "one MultiMesh owns all puff instances")
	_assert(renderer.get_child_count() == 0, "renderer does not create one Godot node per puff")

	var first_transform: Transform3D = renderer.multimesh.get_instance_transform(0)
	var first_scale := Vector3(first_transform.basis.x.length(), first_transform.basis.y.length(), first_transform.basis.z.length())
	_assert(first_scale.x > 100.0 and first_scale.y > 100.0 and first_scale.z > 100.0, "puffs have meaningful 3D thickness")

	# Same LOD, same field: changing camera distance must not resize physical clouds.
	renderer.set_view_state(Vector3.ZERO, 700000.0)
	renderer.set_simulation_seconds(0.0)
	var second_transform: Transform3D = renderer.multimesh.get_instance_transform(0)
	var second_scale := Vector3(second_transform.basis.x.length(), second_transform.basis.y.length(), second_transform.basis.z.length())
	_assert(first_scale.is_equal_approx(second_scale), "camera zoom does not rescale clouds")

	var mesh := renderer.multimesh.mesh as SphereMesh
	_assert(mesh != null and mesh.radial_segments <= 8 and mesh.rings <= 4, "puff mesh stays deliberately low-poly")
	var material := mesh.material as StandardMaterial3D
	_assert(material != null, "cloud puffs share one lightweight material")
	_assert(material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED, "clouds use shared scene lighting instead of duplicated sun math")

	renderer.queue_free()
	await process_frame

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("cloud field test failed: " + message)
	quit(1)
