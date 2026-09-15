extends SceneTree

const TransitionPolicy = preload("res://scripts/geodot_transition_policy.gd")

func _init() -> void:
	# Partial detail residency is prefetch only; it must never steal presentation.
	var partial := {"desired_cells": 12, "active_cells": 20, "ready_desired_cells": 11}
	assert(not TransitionPolicy.detail_ready(partial))
	assert(TransitionPolicy.hold_far(40000.0,55000.0,true,false))
	assert(not TransitionPolicy.detail_owns_presentation(40000.0,55000.0,true,false))

	# The ownership swap is permitted only when every requested detail cell is warm.
	var complete := {"desired_cells": 12, "active_cells": 20, "ready_desired_cells": 12}
	assert(TransitionPolicy.detail_ready(complete))
	assert(not TransitionPolicy.hold_far(40000.0,55000.0,true,true))
	assert(TransitionPolicy.detail_owns_presentation(40000.0,55000.0,true,true))

	# At far distance, far presentation wins even if detail remains resident/warm.
	assert(not TransitionPolicy.detail_owns_presentation(80000.0,55000.0,true,true))
	assert(not TransitionPolicy.hold_far(80000.0,55000.0,true,true))

	# Zero desired coverage can never be treated as a completed detail replacement.
	assert(not TransitionPolicy.detail_ready({"desired_cells":0,"ready_desired_cells":0}))
	print("GEODOT_ATOMIC_OWNERSHIP=PASS")
	quit(0)
