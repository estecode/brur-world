class_name InteractionQuery
extends RefCounted

## Queries and invokes small generic interactable action contracts.
##
## Dependencies:
## - Uses duck-typed available_actions/perform_action APIs only.
## - Does not know about Person roles or object-specific interaction types.

static func available_actions(person, interactable) -> Array[StringName]:
	if interactable == null or not interactable.has_method("available_actions"):
		return []
	var raw_actions = interactable.call("available_actions", person)
	var actions: Array[StringName] = []
	for action in raw_actions:
		actions.append(StringName(action))
	return actions

static func perform(person, interactable, action: StringName) -> bool:
	if interactable == null or not interactable.has_method("perform_action"):
		return false
	if action not in available_actions(person, interactable):
		return false
	return bool(interactable.call("perform_action", person, action))
