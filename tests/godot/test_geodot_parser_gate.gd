extends SceneTree
const WorldRenderer = preload("res://scripts/geodot_world_renderer.gd")
const FarRenderer = preload("res://scripts/geodot_far_renderer.gd")
const TunedMain = preload("res://scripts/geodot_poc_tuned_main.gd")
const HlodController = preload("res://scripts/geodot_hlod_controller.gd")
func _init() -> void:
	print("GEODOT_PARSER_GATE=PASS", WorldRenderer, FarRenderer, TunedMain, HlodController)
	quit(0)
