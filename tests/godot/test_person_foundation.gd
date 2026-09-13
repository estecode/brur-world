extends SceneTree

## Headless deterministic and physics-integration tests for the generic Person foundation.
##
## Dependencies:
## - Production person movement/interaction/occupancy/controller scripts.
## - Production player_person and vehicle scenes for real adapter/collision coverage.

const MovementIntentScript = preload("res://scripts/person_movement_intent.gd")
const MovementModelScript = preload("res://scripts/person_movement_model.gd")
const InteractionQueryScript = preload("res://scripts/interaction_query.gd")
const FixtureInteractableScript = preload("res://tests/godot/fixture_interactable.gd")

var _failures: Array[String] = []
var _collision_seen = null

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_deterministic_movement_and_states()
	_test_surface_traversal_contract()
	await _test_player_controller_and_occupancy()
	await _test_physical_obstacle_collision()
	await _test_vehicle_collision_event()
	if _failures.is_empty():
		print("PERSON_FOUNDATION_TEST=PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		print("PERSON_FOUNDATION_TEST=FAIL count=%d" % _failures.size())
		quit(1)

func _test_deterministic_movement_and_states() -> void:
	var model = MovementModelScript.new()
	var walk = MovementIntentScript.new(Vector2(0.0, -1.0), false)
	var run = MovementIntentScript.new(Vector2(0.0, -1.0), true)
	var idle = MovementIntentScript.new(Vector2.ZERO, false)

	var walk_velocity: Vector2 = model.step(walk, 1.0)
	_assert(is_equal_approx(walk_velocity.length(), model.walk_speed_mps), "walking reaches deterministic walk speed")
	_assert(model.movement_state == MovementModelScript.MovementState.WALKING, "walking intent enters WALKING state")

	var run_velocity: Vector2 = model.step(run, 1.0)
	_assert(is_equal_approx(run_velocity.length(), model.run_speed_mps), "running reaches deterministic run speed")
	_assert(model.movement_state == MovementModelScript.MovementState.RUNNING, "run intent enters RUNNING state")

	var stopped: Vector2 = model.step(idle, 1.0)
	_assert(stopped.is_zero_approx(), "idle intent deterministically decelerates to zero")
	_assert(model.movement_state == MovementModelScript.MovementState.STANDING, "idle intent enters STANDING state")

	model.step(run, 0.1, false, true)
	_assert(model.movement_state == MovementModelScript.MovementState.FALLING, "falling is represented independently of controller role")

	var blocked_model = MovementModelScript.new()
	var blocked_velocity: Vector2 = blocked_model.step(walk, 1.0, true)
	_assert(blocked_velocity.is_zero_approx(), "represented blocked movement does not advance person")

func _test_surface_traversal_contract() -> void:
	var model = MovementModelScript.new()
	_assert(model.can_traverse_surface(MovementModelScript.ROAD), "road is physically traversable")
	_assert(model.can_traverse_surface(MovementModelScript.OPEN_GROUND), "open ground is physically traversable")
	_assert(model.can_traverse_surface(MovementModelScript.FOOTWAY), "footway is physically traversable")
	_assert(model.can_traverse_surface(MovementModelScript.PARKING), "parking is physically traversable")
	_assert(not model.can_traverse_surface(MovementModelScript.BUILDING), "building surface is impassable")
	_assert(not model.can_traverse_surface(MovementModelScript.WALL), "wall surface is impassable")
	_assert(not model.can_traverse_surface(MovementModelScript.FENCE), "fence surface is impassable")
	_assert(not model.can_traverse_surface(MovementModelScript.WATER), "water surface is impassable")

func _test_player_controller_and_occupancy() -> void:
	var person_scene := load("res://scenes/player_person.tscn") as PackedScene
	var vehicle_scene := load("res://scenes/vehicle.tscn") as PackedScene
	_assert(person_scene != null, "production player Person scene loads")
	_assert(vehicle_scene != null, "production Vehicle scene loads")
	if person_scene == null or vehicle_scene == null:
		return

	var root := Node3D.new()
	get_root().add_child(root)
	var person = person_scene.instantiate()
	person.gravity_mps2 = 0.0
	root.add_child(person)
	await process_frame
	var controller = person.get_node_or_null("PlayerPersonController")
	_assert(controller != null, "player input/controller is a separate child from Person physics")
	controller.call("apply_person_intent", Vector2(1.0, 0.0), true)
	_assert(person.movement_model().movement_state == MovementModelScript.MovementState.STANDING, "controller intent is separate from physical step state")

	var car = vehicle_scene.instantiate()
	car.configure(0)
	root.add_child(car)
	var truck = vehicle_scene.instantiate()
	truck.configure(4)
	truck.position = Vector3(10.0, 0.0, 0.0)
	root.add_child(truck)
	await process_frame

	var car_driver = car.get_node_or_null("DriverSeat")
	var car_passenger = car.get_node_or_null("PassengerSeat")
	var truck_driver = truck.get_node_or_null("DriverSeat")
	_assert(car_driver != null and truck_driver != null, "same seat/occupancy model exists on distinct vehicle kinds")
	_assert(bool(car_driver.driver_capable), "driver seat is driver-capable")
	_assert(not bool(car_passenger.driver_capable), "passenger seat is not driver-capable")

	var identity_before: StringName = person.person_id
	_assert(InteractionQueryScript.perform(person, car_driver, &"enter"), "generic interaction enters compatible driver seat")
	_assert(person.current_seat() == car_driver, "Person records generic occupied seat")
	_assert(person.person_id == identity_before, "Person identity survives entering vehicle")
	_assert(controller.call("vehicle_control_target") == car, "driver-capable occupancy exposes vehicle to external controller")
	_assert(bool(controller.call("apply_vehicle_controls", 0.5, 0.0, 0.0)), "external controller can drive through Vehicle public API")

	var second_person = person_scene.instantiate()
	second_person.gravity_mps2 = 0.0
	root.add_child(second_person)
	await process_frame
	_assert(not car_driver.try_enter(second_person), "seat cannot be occupied by two Persons")

	_assert(InteractionQueryScript.perform(person, car_driver, &"exit"), "generic interaction exits occupied seat")
	_assert(person.current_seat() == null, "Person returns to on-foot occupancy state")
	_assert(person.person_id == identity_before, "Person identity survives exit")

	_assert(InteractionQueryScript.perform(person, car_passenger, &"enter"), "same Person can occupy passenger seat")
	_assert(controller.call("vehicle_control_target") == null, "passenger occupancy does not grant vehicle control")
	_assert(not bool(controller.call("apply_vehicle_controls", 1.0, 0.0, 0.0)), "passenger cannot implicitly drive")
	_assert(InteractionQueryScript.perform(person, car_passenger, &"exit"), "passenger can exit through same interaction boundary")

	truck_driver.compatible = false
	_assert(not InteractionQueryScript.perform(person, truck_driver, &"enter"), "incompatible seat entry fails cleanly")
	truck_driver.compatible = true
	_assert(InteractionQueryScript.perform(person, truck_driver, &"enter"), "same occupancy model works for second Vehicle kind")
	_assert(InteractionQueryScript.perform(person, truck_driver, &"exit"), "second Vehicle kind exits through same model")

	var fixture = FixtureInteractableScript.new()
	var fixture_actions := InteractionQueryScript.available_actions(person, fixture)
	_assert(&"use" in fixture_actions, "new interactable type exposes actions without Person methods")
	_assert(not InteractionQueryScript.perform(person, fixture, &"unsupported"), "unsupported interaction action is rejected")
	_assert(InteractionQueryScript.perform(person, fixture, &"use"), "generic interactable action executes through query boundary")
	_assert(fixture.used, "interactable owns object-specific action result")

	root.queue_free()
	await process_frame

func _test_physical_obstacle_collision() -> void:
	var person_scene := load("res://scenes/player_person.tscn") as PackedScene
	if person_scene == null:
		return
	var root := Node3D.new()
	get_root().add_child(root)
	var person = person_scene.instantiate()
	person.gravity_mps2 = 0.0
	root.add_child(person)

	var wall := StaticBody3D.new()
	wall.position = Vector3(0.0, 0.0, -1.5)
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 2.0, 0.4)
	shape_node.position = Vector3(0.0, 1.0, 0.0)
	shape_node.shape = box
	wall.add_child(shape_node)
	root.add_child(wall)
	await physics_frame

	person.call("apply_movement_intent", MovementIntentScript.new(Vector2(0.0, -1.0), false))
	for _frame in 90:
		await physics_frame
	_assert(person.global_position.z > -1.15, "real obstacle collision blocks free-roam movement")
	root.queue_free()
	await process_frame

func _test_vehicle_collision_event() -> void:
	var person_scene := load("res://scenes/player_person.tscn") as PackedScene
	var vehicle_scene := load("res://scenes/vehicle.tscn") as PackedScene
	if person_scene == null or vehicle_scene == null:
		return
	var root := Node3D.new()
	get_root().add_child(root)
	var person = person_scene.instantiate()
	person.gravity_mps2 = 0.0
	root.add_child(person)
	var vehicle = vehicle_scene.instantiate()
	vehicle.position = Vector3(0.0, 0.0, -2.0)
	root.add_child(vehicle)
	_collision_seen = null
	person.collision_event.connect(_on_person_collision)
	await physics_frame

	person.call("apply_movement_intent", MovementIntentScript.new(Vector2(0.0, -1.0), true))
	for _frame in 90:
		await physics_frame
		if _collision_seen != null:
			break
	_assert(_collision_seen != null, "Person/Vehicle physics integration emits a generic collision event")
	_assert(person.global_position.z > -1.7, "production Vehicle collision body blocks Person movement")
	root.queue_free()
	await process_frame

func _on_person_collision(collider) -> void:
	_collision_seen = collider

func _assert(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
