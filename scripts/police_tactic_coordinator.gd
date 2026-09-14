class_name PoliceTacticCoordinator
extends RefCounted

## Coordinates one unit's selected tactic and conservative replanning from shared observations.
##
## Dependencies:
## - Uses PoliceTacticSelector plus injected tactic objects.
## - Emits abstract plans for existing pursuit/routing/driver composition.
## - Owns no Vehicle physics, road graph or observation storage.

const SelectorScript = preload("res://scripts/police_tactic_selector.gd")

var selector = SelectorScript.new()
var active_tactic = null

func add_tactic(tactic) -> void:
	selector.add_tactic(tactic)

func assign(observation: Dictionary) -> Dictionary:
	if active_tactic != null and not bool(active_tactic.call("is_terminal")):
		return active_tactic.call("snapshot") as Dictionary
	var plan := selector.select(observation)
	if plan.is_empty():
		active_tactic = null
		return {"tactic_id": &"intercept", "fallback": true}
	for tactic in selector.tactics:
		if tactic.call("tactic_id") == plan.get("tactic_id", &""):
			active_tactic = tactic
			break
	return plan

func update(observation: Dictionary, delta: float, unit_position: Vector2) -> Dictionary:
	if active_tactic == null:
		return assign(observation)
	if bool(active_tactic.call("should_replan", observation)):
		active_tactic.call("cancel")
		active_tactic = null
		return assign(observation)
	active_tactic.call("step", delta, unit_position)
	return active_tactic.call("snapshot") as Dictionary

func cancel_active() -> void:
	if active_tactic != null and not bool(active_tactic.call("is_terminal")):
		active_tactic.call("cancel")
