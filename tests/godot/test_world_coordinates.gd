extends SceneTree

## Headless deterministic contract tests for shared world-coordinate conversion.
## Dependencies: scripts/world_coordinates.gd only.

const WorldCoordinatesScript = preload("res://scripts/world_coordinates.gd")

func _init() -> void:
	var coordinates = WorldCoordinatesScript.new(Vector2(1000000.0, 6500000.0), 32000.0)

	_assert(coordinates.absolute_to_world(Vector2(1000000.0, 6500000.0)) == Vector3.ZERO, "origin maps to world zero")
	_assert(coordinates.absolute_to_world(Vector2(1000125.0, 6499750.0)) == Vector3(125.0, 0.0, 250.0), "positive and negative offsets preserve axis/sign rules")
	_assert(coordinates.world_to_absolute(Vector3(125.0, 0.0, 250.0)) == Vector2(1000125.0, 6499750.0), "world to absolute inverts the transform")

	var large_absolute := Vector2(2145678.25, 7600123.75)
	var large_world: Vector3 = coordinates.absolute_to_world(large_absolute)
	_assert(coordinates.world_to_absolute(large_world).is_equal_approx(large_absolute), "Sweden-scale coordinates round-trip")

	_assert(coordinates.absolute_to_tile(Vector2(0.0, 0.0)) == Vector2i(0, 0), "absolute origin is tile zero")
	_assert(coordinates.absolute_to_tile(Vector2(31999.999, 31999.999)) == Vector2i(0, 0), "value below positive boundary stays in tile")
	_assert(coordinates.absolute_to_tile(Vector2(32000.0, 32000.0)) == Vector2i(1, 1), "positive boundary advances tile")
	_assert(coordinates.absolute_to_tile(Vector2(-0.001, -0.001)) == Vector2i(-1, -1), "negative fractional position floors into negative tile")
	_assert(coordinates.absolute_to_tile(Vector2(-32000.0, -32000.0)) == Vector2i(-1, -1), "exact negative boundary is deterministic")
	_assert(coordinates.absolute_to_tile(Vector2(-32000.001, -32000.001)) == Vector2i(-2, -2), "value below negative boundary advances negative tile")

	var tile := Vector2i(42, 203)
	var tile_world: Vector3 = coordinates.tile_origin_world(tile, 17.0)
	_assert(tile_world.y == 17.0, "tile world origin preserves requested height")
	_assert(coordinates.world_to_tile(tile_world) == tile, "tile origin round-trips through world coordinates")
	_assert(coordinates.world_to_tile(tile_world) == coordinates.world_to_tile(tile_world), "repeated calls are deterministic")

	print("godot world-coordinate tests: OK")
	quit(0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("world-coordinate test failed: " + message)
	quit(1)
