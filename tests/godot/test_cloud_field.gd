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
	await _test_renderer_structure(model)
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
	var medium_count: int = 0
	var large_count: int = 0
	var smallest_size: float = INF
	var largest_size: float = 0.0
	for y in range(-8, 9):
		for x in range(-8, 9):
			var clouds: Array[Dictionary] = model.generate_cell(Vector2i(x, y), 0.78, 9981)
			for cloud in clouds:
				var profile_name := String(cloud["profile"])
				var bounds: Dictionary = model.profile_bounds(profile_name)
				var size_m: float = float(cloud["size_m"])
				var thickness_m: float = float(cloud["thickness_m"])
				var altitude_m: float = float(cloud["altitude_m_asl"])
				var velocity: Vector3 = cloud["velocity_mps"]
				var speed_mps: float = velocity.length()
				smallest_size = minf(smallest_size, size_m)
				largest_size = maxf(largest_size, size_m)
				_assert(size_m >= float(bounds["size_min_m"]) and size_m <= float(bounds["size_max_m"]), "cloud size stays inside profile bounds")
				_assert(thickness_m >= float(bounds["thickness_min_m"]) and thickness_m <= float(bounds["thickness_max_m"]), "cloud thickness stays inside profile bounds")
				_assert(altitude_m >= float(bounds["altitude_min_m_asl"]) and altitude_m <= float(bounds["altitude_max_m_asl"]), "cloud altitude stays inside profile bounds")
				_assert(speed_mps >= float(bounds["speed_min_mps"]) - 0.001 and speed_mps <= float(bounds["speed_max_mps"]) + 0.001, "cloud speed stays inside profile bounds")
				match profile_name:
					"small_cumulus":
						small_count += 1
					"medium_cumulus":
						medium_count += 1
					"large_low_mid":
						large_count += 1
	_assert(small_count > medium_count, "small clouds remain the most common profile")
	_assert(medium_count > large_count, "medium clouds are more common than rare large formations")
	_assert(large_count > 0, "weighted distribution still includes rare large formations")
	_assert(largest_size / smallest_size > 10.0, "generated field has strong overview-scale size variation")

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

func _test_renderer_structure(model) -> void:
	var renderer = CloudFieldRendererScript.new()
	root.add_child(renderer)
	await process_frame
	renderer.set_view_state(Vector3.ZERO, 800000.0, Vector3(0.0, 800000.0, 0.0))
	renderer.set_simulation_seconds(0.0)
	await process_frame

	var stats: Dictionary = renderer.get_render_stats()
	_assert(int(stats["cloud_count"]) >= 500, "reference full-zoom view contains many distinct cloud formations")
	_assert(int(stats["puff_instance_count"]) > 0, "renderer creates puff instances")
	_assert(int(stats["puff_instance_count"]) <= int(stats["max_puff_instances"]), "renderer respects explicit instance budget")
	_assert(int(stats["max_puff_instances"]) == 2200, "fuller field keeps the same explicit lightweight puff budget")
	_assert(is_equal_approx(float(stats["coverage"]), 0.64), "density increase does not require raising coverage above the tuned value")
	_assert(renderer.multimesh != null and renderer.multimesh.instance_count == int(stats["puff_instance_count"]), "one MultiMesh owns all puff instances")
	_assert(renderer.multimesh.use_colors, "MultiMesh enables per-puff opacity without creating nodes")
	_assert(renderer.get_child_count() == 0, "renderer does not create one Godot node per puff")

	# The headless dummy renderer does not reliably round-trip per-instance
	# MultiMesh transforms. Validate 3D geometry structurally here while the
	# model tests above enforce hundreds of metres of physical thickness.
	var mesh := renderer.multimesh.mesh as SphereMesh
	_assert(mesh != null and mesh.radial_segments <= 8 and mesh.rings <= 4, "puff mesh stays deliberately low-poly")
	var mesh_bounds: AABB = mesh.get_aabb()
	_assert(mesh_bounds.size.x > 0.0 and mesh_bounds.size.y > 0.0 and mesh_bounds.size.z > 0.0, "puff base mesh has real 3D volume")

	# Same LOD and generated field: changing camera distance must not regenerate
	# a different physical cloud set or alter the instance budget.
	var before_count: int = renderer.multimesh.instance_count
	renderer.set_view_state(Vector3.ZERO, 700000.0, Vector3(0.0, 700000.0, 0.0))
	renderer.set_simulation_seconds(0.0)
	_assert(renderer.multimesh.instance_count == before_count, "camera zoom does not change physical cloud population inside one LOD")

	# Put the camera at the center of a deterministic rendered cloud. The central
	# puff is always centered on the cloud, so at least one instance must fade.
	var inside_position := _first_rendered_cloud_position(model, 0.64, 700031)
	_assert(inside_position.is_finite(), "inside-cloud fixture finds a rendered cloud")
	renderer.set_view_state(Vector3.ZERO, 700000.0, inside_position)
	renderer.set_simulation_seconds(0.0)
	var inside_stats: Dictionary = renderer.get_render_stats()
	_assert(int(inside_stats["faded_puff_count"]) > 0, "camera inside a cloud fades nearby puffs for map visibility")
	_assert(int(inside_stats["faded_puff_count"]) < int(inside_stats["puff_instance_count"]), "inside fade is local and leaves distant clouds opaque")

	var material := mesh.material as StandardMaterial3D
	_assert(material != null, "cloud puffs share one lightweight material")
	_assert(material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED, "clouds use shared scene lighting instead of duplicated sun math")
	_assert(material.vertex_color_use_as_albedo, "shared material consumes per-instance alpha for interior fading")

	renderer.queue_free()
	await process_frame

func _first_rendered_cloud_position(model, coverage: float, seed: int) -> Vector3:
	for cell_y in range(-4, 5):
		for cell_x in range(-4, 5):
			var generated: Array[Dictionary] = model.generate_cell(Vector2i(cell_x, cell_y), coverage, seed)
			if not generated.is_empty():
				return generated[0]["position"]
	return Vector3(INF, INF, INF)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("cloud field test failed: " + message)
	quit(1)
