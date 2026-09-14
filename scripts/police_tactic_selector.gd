class_name PoliceTacticSelector
extends RefCounted

## Selects the first available small police tactic object without central special-case branching.
##
## Dependencies:
## - Tactic objects expose tactic_id/request/snapshot.
## - Owns no routing, observations, Vehicle state or tactic implementation details.

var tactics: Array = []

func add_tactic(tactic) -> void:
	if tactic != null and tactic.has_method("request") and tactic.has_method("tactic_id"):
		tactics.append(tactic)

func select(observation: Dictionary) -> Dictionary:
	for tactic in tactics:
		var plan: Dictionary = tactic.call("request", observation)
		if not plan.is_empty():
			return plan
	return {}
