extends Node3D

## Runs the production sun model/adapter with a local debug time fixture before WorldClock exists.
## Dependencies: sun_light_adapter.gd and scene-owned DirectionalLight3D; harness time is test input only, not production world time.

const SunLightAdapterScript = preload("res://scripts/sun_light_adapter.gd")

const STOCKHOLM_LATITUDE := 59.3293
const STOCKHOLM_LONGITUDE := 18.0686

@export var simulated_minutes_per_second := 30.0

@onready var sun: DirectionalLight3D = $DirectionalLight3D
@onready var status_label: Label = $CanvasLayer/PanelContainer/Label

var _adapter
var _local_minutes := 360.0

func _ready() -> void:
	_adapter = SunLightAdapterScript.new()
	add_child(_adapter)
	_adapter.setup(sun)
	_apply_fixture_time()

func _process(delta: float) -> void:
	_local_minutes = fposmod(_local_minutes + delta * simulated_minutes_per_second, 1440.0)
	_apply_fixture_time()

func _apply_fixture_time() -> void:
	var hour := int(floor(_local_minutes / 60.0))
	var minute := int(floor(fposmod(_local_minutes, 60.0)))
	var snapshot := {
		"year": 2026,
		"month": 6,
		"day": 21,
		"hour": hour,
		"minute": minute,
		"second": 0,
		"utc_offset_hours": 2.0,
	}
	var state: Dictionary = _adapter.apply_time_snapshot(snapshot, STOCKHOLM_LATITUDE, STOCKHOLM_LONGITUDE)
	if not bool(state.get("valid", false)):
		status_label.text = "SUN HARNESS: invalid fixture"
		return
	status_label.text = "SUN HARNESS — Stockholm 2026-06-21 %02d:%02d\nAzimuth %.1f°  Elevation %.1f°  Daylight %.1f h" % [
		hour,
		minute,
		float(state["azimuth_deg"]),
		float(state["elevation_deg"]),
		float(state["daylight_minutes"]) / 60.0,
	]
