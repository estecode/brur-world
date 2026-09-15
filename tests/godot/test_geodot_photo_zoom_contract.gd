extends SceneTree

const DetailRenderer = preload("res://scripts/geodot_world_renderer.gd")
const BudgetedRenderer = preload("res://scripts/geodot_budgeted_world_renderer.gd")
const FarRenderer = preload("res://scripts/geodot_far_renderer.gd")

func _init() -> void:
	assert(FarRenderer.fallback_radius_for_distance(82000.0) >= 70000.0)
	assert(FarRenderer.fallback_radius_for_distance(300000.0) >= 250000.0)
	assert(FarRenderer.fallback_radius_for_distance(500000.0) >= 400000.0)

	var renderer := DetailRenderer.new()
	root.add_child(renderer)
	var warm := Node3D.new()
	renderer.add_child(warm)
	renderer.set("_ready", true)
	renderer.set("_active", {"2000.000:0:0": {"node": warm, "lod": 0}})
	renderer.set_presentation_visible(false)
	assert(not warm.visible)
	renderer.set_enabled(false)
	var snapshot: Dictionary = renderer.debug_snapshot()
	assert(snapshot.active_cells == 1)
	assert(not snapshot.presentation_visible)
	renderer.set_presentation_visible(true)
	assert(warm.visible)

	# Desired cells cannot be evicted. Among warm stale cells, least recently used
	# is evicted first so a quick reverse zoom preferentially hits hot geometry.
	var active := {"old":{"lod":0,"last_touch":2}, "new":{"lod":0,"last_touch":9}, "desired":{"lod":0,"last_touch":1}}
	var desired := {"desired":0}
	assert(BudgetedRenderer.choose_lru_stale_eviction_key(active, desired, "incoming") == "old")
	assert(BudgetedRenderer.choose_lru_stale_eviction_key({"desired":{"lod":0,"last_touch":1}}, desired, "incoming").is_empty())

	renderer.shutdown(); renderer.free()
	print("GEODOT_PHOTO_ZOOM_CONTRACT=PASS")
	quit(0)
