extends SceneTree

const DetailRenderer = preload("res://scripts/geodot_world_renderer.gd")
const FarRenderer = preload("res://scripts/geodot_far_renderer.gd")

func _init() -> void:
	# Missing ground-ray intersections at high altitude must never collapse the far
	# query to one zero-area focus cell.
	assert(FarRenderer.fallback_radius_for_distance(82000.0) >= 70000.0)
	assert(FarRenderer.fallback_radius_for_distance(300000.0) >= 250000.0)
	assert(FarRenderer.fallback_radius_for_distance(500000.0) >= 400000.0)

	# A presentation LOD change demotes streaming but retains completed detail.
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

	# Warm cells are evictable only when a bounded resident slot is actually needed;
	# desired cells always outrank stale warm cells.
	var active := {"a":{"lod":0}, "b":{"lod":0}}
	var desired := {"b":0}
	assert(DetailRenderer.choose_stale_eviction_key(active, desired, "c") == "a")
	assert(DetailRenderer.choose_stale_eviction_key({"b":{"lod":0}}, desired, "c").is_empty())

	renderer.shutdown()
	renderer.free()
	print("GEODOT_PHOTO_ZOOM_CONTRACT=PASS")
	quit(0)
