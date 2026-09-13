extends SceneTree

## Headless regression tests for the first Swedish police vehicle profile and emergency presentation state.
##
## Dependencies:
## - Instantiates the production Vehicle scene and PoliceVehicleVisual component.
## - Does not use police AI or a test-only vehicle implementation.

const CAR_KIND: int = 0
const POLICE_CAR_KIND: int = 1
const PLAYER_OWNER: int = 0
const POLICE_PROFILE_ID: StringName = &"se_police_volvo_v90_cc_d5_2017"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://scenes/vehicle.tscn") as PackedScene
	_assert(scene != null, "production vehicle scene loads")
	var vehicle := scene.instantiate() as Node3D
	_assert(vehicle != null, "production Vehicle adapter instantiates")
	get_root().add_child(vehicle)
	vehicle.call("configure", POLICE_CAR_KIND)
	await process_frame

	_assert(StringName(vehicle.call("profile_id")) == POLICE_PROFILE_ID, "police car selects the named Swedish Volvo profile")
	_assert(_approx(float(vehicle.get("length_m")), 4.939, 0.001), "V90 Cross Country length is 4.939 m")
	_assert(_approx(float(vehicle.get("width_m")), 1.879, 0.001), "V90 Cross Country body width is 1.879 m")
	_assert(_approx(float(vehicle.get("height_m")), 1.543, 0.001), "V90 Cross Country height is 1.543 m")
	_assert(_approx(float(vehicle.get("mass_kg")), 1950.0, 0.01), "police equipment mass approximation is explicit")
	_assert(_approx(float(vehicle.get("max_speed_mps")) * 3.6, 230.0, 0.01), "D5 profile top speed is 230 km/h")
	_assert(String(vehicle.get("energy_type")) == "diesel", "D5 profile uses diesel")
	_assert(_approx(float(vehicle.get("energy_capacity")), 60.0, 0.01), "D5 profile uses the documented 60 l tank")

	var visual := vehicle.get_node_or_null("VisualRoot/PoliceEmergencyVisual")
	_assert(visual != null, "production vehicle contains police presentation component")
	_assert(bool(visual.call("police_profile_active")), "police livery activates for the named profile")
	_assert(not vehicle.get_node("VisualRoot/Body").visible, "civilian body is hidden for police profile")
	_assert(vehicle.get_node("VisualRoot/PoliceEmergencyVisual/Livery").visible, "police livery is visible")
	_assert(vehicle.get_node_or_null("VisualRoot/PoliceEmergencyVisual/Left/RoofFrontLeft") != null, "left roof blue module exists")
	_assert(vehicle.get_node_or_null("VisualRoot/PoliceEmergencyVisual/Right/RoofFrontRight") != null, "right roof blue module exists")
	_assert(vehicle.get_node_or_null("VisualRoot/PoliceEmergencyVisual/Left/GrilleLeft") != null, "left grille blue module exists")
	_assert(vehicle.get_node_or_null("VisualRoot/PoliceEmergencyVisual/Right/GrilleRight") != null, "right grille blue module exists")

	_assert(not bool(vehicle.call("emergency_lights_active")), "blue lights start off")
	_assert(not bool(vehicle.call("siren_active")), "siren starts off independently")
	_assert(bool(vehicle.call("set_emergency_lights_active", true)), "police gameplay can request blue lights")
	_assert(bool(vehicle.call("emergency_lights_active")), "blue-light state is exposed")
	_assert(not bool(vehicle.call("siren_active")), "blue lights do not implicitly enable siren")
	_assert(bool(vehicle.call("set_siren_active", true)), "police gameplay can request siren separately")
	_assert(bool(vehicle.call("siren_active")), "siren state is exposed independently")

	var left := vehicle.get_node("VisualRoot/PoliceEmergencyVisual/Left") as Node3D
	var right := vehicle.get_node("VisualRoot/PoliceEmergencyVisual/Right") as Node3D
	_assert(left.visible and not right.visible, "flash pattern starts with left-side modules")
	visual.call("advance_pattern", 0.12)
	_assert(not left.visible and not right.visible, "double-flash pattern includes deliberate dark interval")
	visual.call("advance_pattern", 0.12)
	_assert(left.visible and not right.visible, "left-side second pulse repeats deterministically")
	visual.call("advance_pattern", 0.24)
	_assert(not left.visible and right.visible, "pattern switches to right-side double pulse deterministically")
	visual.call("advance_pattern", 0.48)
	_assert(left.visible and not right.visible, "eight-step flash pattern loops exactly")

	vehicle.call("set_world_position", Vector3.ZERO)
	vehicle.call("set_motion_state", 0.0, 0.0)
	_assert(bool(vehicle.call("set_control_inputs", PLAYER_OWNER, 1.0, 0.0, 0.0)), "police profile uses shared Vehicle control API")
	for _index in range(450):
		vehicle.call("_physics_process", 1.0 / 60.0)
	_assert(_approx(float(vehicle.call("speed_kmh")), 100.0, 0.7), "police profile reaches approximately 100 km/h in sourced 7.5 s")

	vehicle.call("configure", CAR_KIND)
	visual.call("_process", 0.0)
	_assert(not bool(visual.call("police_profile_active")), "police presentation turns off when shared Vehicle changes profile")
	_assert(vehicle.get_node("VisualRoot/Body").visible, "civilian body returns for ordinary car profile")
	_assert(not bool(vehicle.call("set_emergency_lights_active", true)), "ordinary car cannot enable police blue lights")
	_assert(not bool(vehicle.call("set_siren_active", true)), "ordinary car cannot enable emergency siren state")

	vehicle.queue_free()
	print("godot police-vehicle tests: OK")
	quit(0)

func _approx(actual: float, expected: float, tolerance: float) -> bool:
	return absf(actual - expected) <= tolerance

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("police-vehicle test failed: " + message)
	quit(1)
