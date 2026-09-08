extends SceneTree

## Verifies the GPS route adapter's one-second failure metrics contract.
##
## Dependencies:
## - Instantiates gps_route_layer.gd without entering the SceneTree.
## - Does not start native routing or require world data.

const GpsRouteLayerScript = preload("res://scripts/gps_route_layer.gd")

func _initialize() -> void:
	var layer: Node = GpsRouteLayerScript.new()
	layer.set("perf_queries", 2)
	layer.set("perf_failures", 1)
	layer.set("perf_last_success", false)
	layer.set("perf_last_failure_reason", "unreachable")
	layer.set("perf_last_failed_leg", 2)

	var metrics: Dictionary = layer.call("consume_perf_metrics") as Dictionary
	assert(int(metrics.get("gps_queries", -1)) == 2)
	assert(int(metrics.get("gps_failures", -1)) == 1)
	assert(bool(metrics.get("gps_last_success", true)) == false)
	assert(str(metrics.get("gps_failure_reason", "")) == "unreachable")
	assert(int(metrics.get("gps_failed_leg", -1)) == 2)

	var reset: Dictionary = layer.call("consume_perf_metrics") as Dictionary
	assert(int(reset.get("gps_queries", -1)) == 0)
	assert(int(reset.get("gps_failures", -1)) == 0)
	assert(str(reset.get("gps_failure_reason", "missing")) == "")
	assert(int(reset.get("gps_failed_leg", 99)) == -1)

	layer.free()
	print("godot gps failure-metrics tests: OK")
	quit(0)
