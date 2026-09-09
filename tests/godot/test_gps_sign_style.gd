extends SceneTree

## Verifies deterministic Swedish GPS sign mapping and navigation-label preservation.
##
## Dependencies:
## - Uses the production GpsSignStyle policy only.
## - Requires no rendering, routing data or native process.

const SignStyle = preload("res://scripts/gps_sign_style.gd")

func _init() -> void:
	assert(SignStyle.category({"highway": "motorway"}) == SignStyle.MOTORWAY)
	assert(SignStyle.category({"highway": "primary"}) == SignStyle.MAJOR_ROAD)
	assert(SignStyle.category({"highway": "residential"}) == SignStyle.LOCAL_ROAD)
	assert(SignStyle.category({"highway": "cycleway"}) == SignStyle.SPECIAL_USE)
	assert(SignStyle.category({}) == SignStyle.LOCAL_ROAD)

	var motorway := SignStyle.presentation({"highway": "motorway"})
	assert(motorway["background"] == Color("#16723b"))
	assert(motorway["foreground"] == Color.WHITE)
	assert(motorway["border"] == Color.WHITE)
	assert(SignStyle.presentation({"highway": "motorway"}) == motorway)

	assert(SignStyle.label({"highway": "motorway", "ref": "E4", "destination": "Stockholm"}) == "E4  Stockholm")
	assert(SignStyle.label({"highway": "motorway_link", "exit_ref": "19", "destination": "Lund N"}) == "Avfart 19  Lund N")
	assert(SignStyle.label({"highway": "primary", "destination_ref": "E22", "destination": "Malmö"}) == "E22  Malmö")
	assert(SignStyle.label({"highway": "residential", "name": "Storgatan"}) == "Storgatan")
	assert(SignStyle.label({}) == "")

	# Sign policy is presentation-only: input metadata is unchanged and carries no legality decision.
	var special := {"highway": "cycleway", "ref": "C1", "routing_legal": false}
	var before := special.duplicate(true)
	SignStyle.presentation(special)
	assert(special == before)
	quit(0)
