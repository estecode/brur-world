extends RefCounted

## Minimal test-only interactable proving new action types do not require Person changes.
## Dependencies: none; consumed only through InteractionQuery's generic contract.

var used: bool = false

func available_actions(_person) -> Array[StringName]:
	return [&"use"]

func perform_action(_person, action: StringName) -> bool:
	if action != &"use":
		return false
	used = true
	return true
