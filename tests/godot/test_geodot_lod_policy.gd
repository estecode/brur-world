extends SceneTree

const Policy = preload("res://scripts/geodot_lod_policy.gd")

func _init() -> void:
	assert(Policy.representation_for_building(2500.0, 10.0, 8.0, 2.0, 1.0, 4.0, 3000.0, 30.0, 6000.0, 300000.0) == Policy.MODE_FULL_3D)
	assert(Policy.representation_for_building(5500.0, 30.0, 36.0, 4.0, 1.0, 4.0, 3000.0, 30.0, 6000.0, 300000.0) == Policy.MODE_FULL_3D)
	assert(Policy.representation_for_building(80000.0, 10.0, 8.0, 40.0, 1.0, 4.0, 3000.0, 30.0, 6000.0, 300000.0) == Policy.MODE_AGGREGATE)
	assert(Policy.representation_for_building(300000.0, 400.0, 80.0, 180.0, 1.0, 4.0, 3000.0, 30.0, 6000.0, 300000.0) == Policy.MODE_AGGREGATE)
	assert(Policy.sample_budget(1000, 0.5, 2000) == 500)
	assert(Policy.sample_budget(1000, 3.0, 2000) == 2000)
	assert(is_equal_approx(Policy.ram_pressure(2_000, 2_000, 3_000), 0.0))
	assert(is_equal_approx(Policy.ram_pressure(2_500, 2_000, 3_000), 0.5))
	assert(Policy.quality_scale_for_pressure(1.0) >= 0.25)
	print("GEODOT_LOD_POLICY=PASS")
	quit()
