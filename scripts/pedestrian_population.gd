class_name PedestrianPopulation
extends Node3D

## Promotes nearby logical pedestrian agents to the production Person scene and demotes distant ones.
##
## Dependencies:
## - Owns PedestrianAgent instances supplied explicitly by composition.
## - Instantiates the generic production Person scene; contains no pedestrian route, world, traffic, or player policy.

const PersonScene = preload("res://scenes/person.tscn")

@export var promote_distance_m: float = 35.0
@export var demote_distance_m: float = 45.0

var _agents: Dictionary = {}
var _full_people: Dictionary = {}

func add_agent(agent) -> bool:
	if agent == null:
		return false
	var person_id := StringName(agent.get("person_id"))
	if person_id == &"" or _agents.has(person_id):
		return false
	_agents[person_id] = agent
	return true

func remove_agent(person_id: StringName) -> bool:
	if not _agents.has(person_id):
		return false
	if _full_people.has(person_id):
		_demote(person_id)
	_agents.erase(person_id)
	return true

func update_relevance(focus_position: Vector3) -> void:
	for person_id_variant in _agents.keys():
		var person_id := StringName(person_id_variant)
		var agent = _agents[person_id]
		var position: Vector3 = agent.position
		if _full_people.has(person_id):
			var full_person = _full_people[person_id]
			if is_instance_valid(full_person):
				position = full_person.global_position
			if position.distance_to(focus_position) > demote_distance_m:
				_demote(person_id)
		elif position.distance_to(focus_position) <= promote_distance_m:
			_promote(person_id)

func full_person(person_id: StringName):
	return _full_people.get(person_id, null)

func logical_agent(person_id: StringName):
	return _agents.get(person_id, null)

func is_promoted(person_id: StringName) -> bool:
	return _full_people.has(person_id)

func lightweight_count() -> int:
	return _agents.size() - _full_people.size()

func full_count() -> int:
	return _full_people.size()

func _promote(person_id: StringName) -> void:
	if _full_people.has(person_id) or not _agents.has(person_id):
		return
	var person = PersonScene.instantiate()
	_agents[person_id].apply_to_person(person)
	add_child(person)
	_full_people[person_id] = person

func _demote(person_id: StringName) -> void:
	if not _full_people.has(person_id) or not _agents.has(person_id):
		return
	var person = _full_people[person_id]
	if is_instance_valid(person):
		_agents[person_id].capture_person(person)
		person.queue_free()
	_full_people.erase(person_id)
