extends "res://scripts/debug_overlay.gd"

## POC-only diagnostics. The production overlay remains untouched; when this
## renderer is selected the panel explicitly reports GeoDot lifecycle state.

func _process(delta: float) -> void:
	super._process(delta)
	if main == null or not main.has_method("geodot_debug_snapshot"): return
	var snapshot: Dictionary = main.call("geodot_debug_snapshot")
	if snapshot.is_empty(): return
	label.text += "\nGEODOT: LOD %s   active/desired %d/%d   stale %d\n" % [String(snapshot.get("screen_lod","?")), int(snapshot.get("active_cells",0)), int(snapshot.get("desired_cells",0)), int(snapshot.get("stale_cells",0))]
	label.text += "GeoDot pipeline: pending %d   ready %d   workers %d   query cache %d\n" % [int(snapshot.get("pending_cells",0)), int(snapshot.get("ready_cells",0)), int(snapshot.get("query_workers",0)), int(snapshot.get("query_cache_cells",0))]
	label.text += "GeoDot bounds: resident <= %d   pending <= %d   ready <= %d" % [int(snapshot.get("max_resident_cells",0)), int(snapshot.get("max_pending_cells",0)), int(snapshot.get("max_ready_cells",0))]
