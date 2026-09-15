extends SceneTree

const Renderer = preload("res://scripts/geodot_world_renderer.gd")
const TransitionPolicy = preload("res://scripts/geodot_transition_policy.gd")

var _failed := false

func _init() -> void: call_deferred("_run")
func _run() -> void:
	_test_contraction_is_ready_to_retire(); _test_pan_keeps_old_coverage_until_replacement(); _test_lod_change_keeps_old_coverage_until_replacement(); _test_prefetch_is_early(); _test_far_waits_for_complete_detail()
	if _failed: quit(1); return
	print("geodot streaming transition contracts: OK"); quit(0)

func _test_contraction_is_ready_to_retire() -> void:
	var active := {"0:0":{"lod":1},"1:0":{"lod":1},"2:0":{"lod":1}}; var desired := {"0:0":1}
	_assert(Renderer.desired_coverage_ready(active,desired),"coverage contraction is immediately ready when retained desired cells already match")
func _test_pan_keeps_old_coverage_until_replacement() -> void:
	var active := {"0:0":{"lod":1},"1:0":{"lod":1},"2:0":{"lod":1}}; var desired := {"1:0":1,"2:0":1,"3:0":1}
	_assert(not Renderer.desired_coverage_ready(active,desired),"pan cannot retire old visible coverage while a replacement cell is missing"); active["3:0"]={"lod":1}; _assert(Renderer.desired_coverage_ready(active,desired),"pan may retire stale coverage after every desired replacement is resident")
func _test_lod_change_keeps_old_coverage_until_replacement() -> void:
	var active := {"0:0":{"lod":0},"1:0":{"lod":0}}; var desired := {"0:0":1,"1:0":1}
	_assert(not Renderer.desired_coverage_ready(active,desired),"LOD transition cannot treat same-key old geometry as the requested replacement"); active["0:0"]={"lod":1}; active["1:0"]={"lod":1}; _assert(Renderer.desired_coverage_ready(active,desired),"LOD transition becomes ready only after all desired representations match")
func _test_prefetch_is_early() -> void:
	_assert(is_equal_approx(TransitionPolicy.prefetch_distance(55000.0,1.35),74250.0),"default prefetch begins well before visible far handoff")
func _test_far_waits_for_complete_detail() -> void:
	var warming := {"desired_cells":128,"active_cells":140,"ready_desired_cells":127}; var ready := {"desired_cells":128,"active_cells":140,"ready_desired_cells":128}
	_assert(not TransitionPolicy.detail_ready(warming),"partial detail cannot replace the far owner even when many stale cells are resident")
	_assert(TransitionPolicy.hold_far(40000.0,55000.0,true,false),"far world remains sole visible owner while detail warms")
	_assert(TransitionPolicy.detail_ready(ready),"detail becomes eligible only when complete requested coverage is resident")
	_assert(not TransitionPolicy.hold_far(40000.0,55000.0,true,true),"far owner may release atomically after complete detail is resident")
	_assert(TransitionPolicy.detail_owns_presentation(40000.0,55000.0,true,true),"detail owns presentation after the atomic handoff")
func _assert(condition: bool, message: String) -> void:
	if condition:return
	_failed=true; push_error("ASSERT FAILED: "+message)
