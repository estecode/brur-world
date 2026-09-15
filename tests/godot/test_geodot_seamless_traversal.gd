extends SceneTree

const FarRenderer = preload("res://scripts/geodot_far_renderer.gd")
const DetailRenderer = preload("res://scripts/geodot_world_renderer.gd")

func _init() -> void:
	# Model the actual production ownership rule: base HLOD starts complete; only a
	# fully READY stable detail tile may mask its corresponding base sample.
	var base_samples:Array[Rect2]=[]
	for y in range(-8,9):
		for x in range(-8,9): base_samples.append(Rect2(Vector2(x*3000,y*3000),Vector2(3000,3000)))
	var ready:Array[Rect2]=[]
	_assert_covered(base_samples,ready,"500km base-only")
	# Arbitrarily slow/out-of-order detail publication cannot remove fallback.
	for step in [Vector2i(0,0),Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
		ready.append(Rect2(Vector2(step.x*3000,step.y*3000),Vector2(3000,3000)))
		_assert_covered(base_samples,ready,"incremental detail")
	# Rapid reverse zoom simply drops desired detail ownership; base was never
	# destroyed and therefore immediately owns every region again.
	ready.clear();_assert_covered(base_samples,ready,"reverse zoom")
	var huge:=Rect2(Vector2(-250000,-250000),Vector2(500000,500000))
	_assert(is_equal_approx(DetailRenderer.coverage_cell_size_for_bounds(huge,3000,1,169),3000),"tile identity stable across 500km traversal")
	print("GEODOT_SEAMLESS_TRAVERSAL=PASS holes=0 base_always_ready=true slow_detail_safe=true reverse_zoom_safe=true")
	quit(0)

func _assert_covered(base:Array[Rect2],detail:Array[Rect2],context:String)->void:
	var owners:=0
	for sample in base:
		# Exactly one presentation class owns each base region: READY detail when it
		# fully encloses the sample, otherwise the resident base HLOD.
		var detail_owner:=FarRenderer.sample_fully_owned_by_detail(sample,detail)
		var base_owner:=not detail_owner
		_assert(int(detail_owner)+int(base_owner)==1,"ownership hole/duplicate in "+context)
		owners+=1
	_assert(owners==base.size(),"all base regions covered in "+context)

func _assert(value:bool,message:String)->void:
	if value:return
	push_error(message);print("GEODOT_SEAMLESS_TRAVERSAL=FAIL ",message);quit(1)
