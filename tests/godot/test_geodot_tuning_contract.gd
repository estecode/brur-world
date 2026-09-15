extends SceneTree

const PanelScript = preload("res://scripts/geodot_tuning_panel.gd")
const FarCache = preload("res://scripts/geodot_far_cache.gd")

func _init() -> void:
	var panel := PanelScript.new(); root.add_child(panel); await process_frame
	assert(panel.anchor_left == 1.0 and panel.anchor_right == 1.0)
	assert(panel.offset_right < 0.0)
	var help_count := 0
	for node in panel.find_children("*","Button",true,false):
		if (node as Button).text == "?":
			help_count += 1; assert(not (node as Button).tooltip_text.is_empty())
	assert(help_count >= 10)
	var tuning: Dictionary = panel.snapshot(); assert(int(tuning.ram_hard_mb) >= int(tuning.ram_target_mb)); assert(float(tuning.streaming_ms) > 0.0)
	var path := "user://geodot-far-fixture.json"
	var file := FileAccess.open(path,FileAccess.WRITE); file.store_string('{"schema":1,"source":{"fingerprint":"fixture"},"levels":[{"cell_m":2000,"cells":[[0,0,10,1000000,100],[1,0,2,10000,20]]},{"cell_m":4000,"cells":[[0,0,12,1010000,100]]}]}'); file.close()
	var cache := FarCache.new(); assert(cache.open(path).get("ok",false)); assert(cache.choose_level(3000.0)==1)
	var samples := cache.query_bounds(Rect2(Vector2.ZERO,Vector2(3999,1999)),0,1,1.0); assert(samples.size()==1); assert(int(samples[0].count)==10)
	cache.close(); DirAccess.remove_absolute(ProjectSettings.globalize_path(path)); panel.free()
	print("GEODOT_TUNING_CONTRACT=PASS"); quit()
