extends RefCounted

## Applies shared non-overlapping viewport slots to persistent overlay windows.
##
## Dependencies:
## - Operates only on Godot Control anchors/offsets in presentation code.
## - Does not depend on gameplay, routing, world state, or subsystem internals.

const MARGIN: float = 14.0
const HEADER_HEIGHT: float = 32.0
const HEADER_GAP: float = 6.0

enum Slot {
	TOP_LEFT,
	TOP_RIGHT,
	BOTTOM_LEFT,
	BOTTOM_RIGHT,
}

static func apply_window(header: Control, body: Control, slot: int, width: float) -> void:
	_apply_horizontal(header, slot, width)
	_apply_horizontal(body, slot, width)
	header.custom_minimum_size = Vector2(width, HEADER_HEIGHT)
	body.custom_minimum_size.x = width

	match slot:
		Slot.TOP_LEFT, Slot.TOP_RIGHT:
			header.anchor_top = 0.0
			header.anchor_bottom = 0.0
			header.offset_top = MARGIN
			header.offset_bottom = MARGIN + HEADER_HEIGHT
			body.anchor_top = 0.0
			body.anchor_bottom = 0.0
			body.offset_top = MARGIN + HEADER_HEIGHT + HEADER_GAP
			body.offset_bottom = body.offset_top
			body.grow_vertical = Control.GROW_DIRECTION_END
		Slot.BOTTOM_LEFT, Slot.BOTTOM_RIGHT:
			header.anchor_top = 1.0
			header.anchor_bottom = 1.0
			header.offset_top = -MARGIN - HEADER_HEIGHT
			header.offset_bottom = -MARGIN
			body.anchor_top = 1.0
			body.anchor_bottom = 1.0
			body.offset_top = -MARGIN - HEADER_HEIGHT - HEADER_GAP
			body.offset_bottom = body.offset_top
			body.grow_vertical = Control.GROW_DIRECTION_BEGIN

	header.reset_size()
	body.reset_size()

static func _apply_horizontal(control: Control, slot: int, width: float) -> void:
	if slot == Slot.TOP_LEFT or slot == Slot.BOTTOM_LEFT:
		control.anchor_left = 0.0
		control.anchor_right = 0.0
		control.offset_left = MARGIN
		control.offset_right = MARGIN + width
		control.grow_horizontal = Control.GROW_DIRECTION_END
	else:
		control.anchor_left = 1.0
		control.anchor_right = 1.0
		control.offset_left = -MARGIN - width
		control.offset_right = -MARGIN
		control.grow_horizontal = Control.GROW_DIRECTION_BEGIN
