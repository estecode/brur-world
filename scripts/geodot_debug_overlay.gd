extends "res://scripts/debug_overlay.gd"

func _process(delta: float) -> void:
	super._process(delta)
	if main == null or not main.has_method("geodot_debug_snapshot"): return
	var snapshot: Dictionary = main.call("geodot_debug_snapshot")
	if snapshot.is_empty(): return
	label.text += "\nGEODOT: LOD %s   active/desired %d/%d   stale %d\n" % [String(snapshot.get("screen_lod","?")),int(snapshot.get("active_cells",0)),int(snapshot.get("desired_cells",0)),int(snapshot.get("stale_cells",0))]
	label.text += "GeoDot pipeline: pending %d   ready %d   workers %d   query cache %d\n" % [int(snapshot.get("pending_cells",0)),int(snapshot.get("ready_cells",0)),int(snapshot.get("query_workers",0)),int(snapshot.get("query_cache_cells",0))]
	label.text += "GeoDot bounds: resident <= %d   pending <= %d   ready <= %d\n" % [int(snapshot.get("max_resident_cells",0)),int(snapshot.get("max_pending_cells",0)),int(snapshot.get("max_ready_cells",0))]
	var far: Dictionary = snapshot.get("far",{})
	if not far.is_empty(): label.text += "Far aggregate: %s  level %d  cell %.0fm  samples %d/%d  %.2fm/px  build %.2fms" % ["ON" if far.get("active",false) else "off",int(far.get("level",-1)),float(far.get("cell_m",0.0)),int(far.get("samples",0)),int(far.get("sample_budget",0)),float(far.get("meters_per_pixel",0.0)),float(far.get("build_ms",0.0))]
