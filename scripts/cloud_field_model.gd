extends RefCounted

## Generates deterministic, clustered cloud state in real-world units.
##
## Dependencies:
## - Uses only deterministic Godot value types and RandomNumberGenerator.
## - Does not depend on SceneTree, rendering, camera state, weather, or astronomy.

const CELL_SIZE_M: float = 200000.0
const MAX_CLOUDS_PER_CELL: int = 42
const DEFAULT_SEED: int = 700031
const SMALL_PROFILE_WEIGHT: float = 0.54
const MEDIUM_PROFILE_WEIGHT: float = 0.30
const LARGE_PROFILE_WEIGHT: float = 0.14

const SMALL_PROFILE := {
	"name": "small_cumulus",
	"size_min_m": 700.0,
	"size_max_m": 2800.0,
	"thickness_min_m": 350.0,
	"thickness_max_m": 1000.0,
	"altitude_min_m_asl": 1200.0,
	"altitude_max_m_asl": 2600.0,
	"speed_min_mps": 6.0,
	"speed_max_mps": 12.0,
	"heading_degrees": 65.0,
}

const MEDIUM_PROFILE := {
	"name": "medium_cumulus",
	"size_min_m": 3200.0,
	"size_max_m": 7500.0,
	"thickness_min_m": 700.0,
	"thickness_max_m": 1800.0,
	"altitude_min_m_asl": 1500.0,
	"altitude_max_m_asl": 3400.0,
	"speed_min_mps": 8.0,
	"speed_max_mps": 15.0,
	"heading_degrees": 72.0,
}

const LARGE_PROFILE := {
	"name": "large_low_mid",
	"size_min_m": 8500.0,
	"size_max_m": 22000.0,
	"thickness_min_m": 1400.0,
	"thickness_max_m": 3400.0,
	"altitude_min_m_asl": 2200.0,
	"altitude_max_m_asl": 5200.0,
	"speed_min_mps": 10.0,
	"speed_max_mps": 18.0,
	"heading_degrees": 80.0,
}

const GIANT_PROFILE := {
	"name": "giant_cloud_bank",
	"size_min_m": 30000.0,
	"size_max_m": 88000.0,
	"thickness_min_m": 2200.0,
	"thickness_max_m": 6200.0,
	"altitude_min_m_asl": 2800.0,
	"altitude_max_m_asl": 6500.0,
	"speed_min_mps": 11.0,
	"speed_max_mps": 20.0,
	"heading_degrees": 84.0,
}

func normalized_coverage(coverage: float) -> float:
	return clampf(coverage, 0.0, 1.0)

func generate_cell(cell: Vector2i, coverage: float, seed: int = DEFAULT_SEED) -> Array[Dictionary]:
	var safe_coverage: float = normalized_coverage(coverage)
	if safe_coverage <= 0.0:
		return []

	var rng := RandomNumberGenerator.new()
	rng.seed = _cell_seed(cell, seed)

	# Stable per-cell density preserves gaps while the larger cloud capacity
	# produces roughly three times as many formations at the tuned coverage.
	var local_density: float = clampf(safe_coverage * rng.randf_range(0.48, 1.58), 0.0, 1.0)
	if rng.randf() > minf(0.94, 0.40 + safe_coverage * 0.72):
		local_density *= 0.08
	var cloud_count: int = int(round(float(MAX_CLOUDS_PER_CELL) * local_density))
	if cloud_count <= 0:
		return []

	# Many compact cluster centres create dense weather regions while keeping
	# distinct open gaps between neighbouring groups.
	var cluster_count: int = clampi(int(ceil(float(cloud_count) / 4.0)), 2, 11)
	var cluster_centers: Array[Vector2] = []
	for _cluster_index in range(cluster_count):
		cluster_centers.append(Vector2(
			rng.randf_range(0.08, 0.92) * CELL_SIZE_M,
			rng.randf_range(0.08, 0.92) * CELL_SIZE_M
		))

	var result: Array[Dictionary] = []
	for cloud_index in range(cloud_count):
		var profile: Dictionary = _pick_profile(rng.randf())
		var center: Vector2 = cluster_centers[cloud_index % cluster_centers.size()]
		var angle: float = rng.randf_range(0.0, TAU)
		var radius: float = sqrt(rng.randf()) * CELL_SIZE_M * 0.10
		var local: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
		local.x = fposmod(local.x, CELL_SIZE_M)
		local.y = fposmod(local.y, CELL_SIZE_M)

		var size_m: float = rng.randf_range(float(profile["size_min_m"]), float(profile["size_max_m"]))
		var thickness_m: float = rng.randf_range(float(profile["thickness_min_m"]), float(profile["thickness_max_m"]))
		var altitude_m: float = rng.randf_range(float(profile["altitude_min_m_asl"]), float(profile["altitude_max_m_asl"]))
		var speed_mps: float = rng.randf_range(float(profile["speed_min_mps"]), float(profile["speed_max_mps"]))
		var heading: float = deg_to_rad(float(profile["heading_degrees"]) + rng.randf_range(-7.0, 7.0))
		var velocity := Vector3(cos(heading) * speed_mps, 0.0, sin(heading) * speed_mps)
		var cell_origin := Vector2(float(cell.x) * CELL_SIZE_M, float(cell.y) * CELL_SIZE_M)

		result.append({
			"profile": String(profile["name"]),
			"cell": cell,
			"position": Vector3(cell_origin.x + local.x, altitude_m, cell_origin.y + local.y),
			"size_m": size_m,
			"thickness_m": thickness_m,
			"altitude_m_asl": altitude_m,
			"velocity_mps": velocity,
			"puff_seed": int(rng.randi()),
		})
	return result

func position_at(cloud: Dictionary, simulation_seconds: float) -> Vector3:
	# Motion remains continuous across generation-cell boundaries. Spatial cells
	# own deterministic initial placement only; they are not runtime walls.
	var base: Vector3 = cloud["position"]
	var velocity: Vector3 = cloud["velocity_mps"]
	return base + velocity * maxf(0.0, simulation_seconds)

func profile_bounds(profile_name: String) -> Dictionary:
	if profile_name == String(SMALL_PROFILE["name"]):
		return SMALL_PROFILE
	if profile_name == String(MEDIUM_PROFILE["name"]):
		return MEDIUM_PROFILE
	if profile_name == String(LARGE_PROFILE["name"]):
		return LARGE_PROFILE
	if profile_name == String(GIANT_PROFILE["name"]):
		return GIANT_PROFILE
	return {}

func _pick_profile(value: float) -> Dictionary:
	if value < SMALL_PROFILE_WEIGHT:
		return SMALL_PROFILE
	if value < SMALL_PROFILE_WEIGHT + MEDIUM_PROFILE_WEIGHT:
		return MEDIUM_PROFILE
	if value < SMALL_PROFILE_WEIGHT + MEDIUM_PROFILE_WEIGHT + LARGE_PROFILE_WEIGHT:
		return LARGE_PROFILE
	return GIANT_PROFILE

func _cell_seed(cell: Vector2i, seed: int) -> int:
	var key := "%d:%d:%d" % [seed, cell.x, cell.y]
	return int(hash(key)) & 0x7fffffff
