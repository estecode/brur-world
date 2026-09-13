extends SceneTree

## Verifies the driving harness exposes runtime Normal/Aggressive/Maniac selection through the production route follower.
## Dependencies: production-backed driving harness scene and VehicleRouteFollower driving-mode API.

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://harness/driving/driving_harness.tscn") as PackedScene
	_assert(scene != null, "driving harness scene loads")
	var harness := scene.instantiate()
	get_root().add_child(harness)
	await process_frame

	var selector := harness.get_node_or_null("Ui/Panel/Margin/VBox/DrivingMode") as OptionButton
	var player := harness.get_node_or_null("PlayerVehicle")
	_assert(selector != null, "driving harness exposes a policy selector")
	_assert(selector.item_count == 3, "driving harness exposes exactly three policy modes")
	_assert(selector.get_item_text(0) == "Normal", "first policy is Normal")
	_assert(selector.get_item_text(1) == "Aggressive", "second policy is Aggressive")
	_assert(selector.get_item_text(2) == "Maniac", "third policy is Maniac")
	_assert(player != null, "driving harness uses the production player vehicle")
	var follower := player.get_node_or_null("VehicleRouteFollower")
	_assert(follower != null, "driving harness uses the production route follower")

	for index in range(3):
		selector.select(index)
		selector.item_selected.emit(index)
		await process_frame
		_assert(int(follower.call("driving_mode")) == selector.get_item_id(index), "selector updates production route-follower policy mode")
		_assert(harness.get_node_or_null("PlayerVehicle") == player, "mode switching keeps the same production vehicle instance")

	harness.queue_free()
	print("DRIVING_HARNESS_MODES=PASS")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("driving-harness mode test failed: " + message)
	quit(1)
