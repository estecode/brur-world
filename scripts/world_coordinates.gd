extends RefCounted

## Owns deterministic conversion between projected absolute, Godot world, and tile coordinates.
##
## Dependencies:
## - Uses only configured origin/tile size and Godot value types.
## - Does not depend on rendering, camera state, routing, file I/O, or SceneTree nodes.

var origin: Vector2
var tile_size: float

func _init(world_origin: Vector2, world_tile_size: float) -> void:
	assert(world_tile_size > 0.0, "WorldCoordinates tile size must be positive")
	origin = world_origin
	tile_size = world_tile_size

func absolute_to_world(absolute_position: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(
		absolute_position.x - origin.x,
		height,
		-(absolute_position.y - origin.y)
	)

func world_to_absolute(world_position: Vector3) -> Vector2:
	return Vector2(
		world_position.x + origin.x,
		-world_position.z + origin.y
	)

func absolute_to_tile(absolute_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(absolute_position.x / tile_size),
		floori(absolute_position.y / tile_size)
	)

func world_to_tile(world_position: Vector3) -> Vector2i:
	return absolute_to_tile(world_to_absolute(world_position))

func tile_origin_absolute(tile: Vector2i) -> Vector2:
	return Vector2(float(tile.x) * tile_size, float(tile.y) * tile_size)

func tile_origin_world(tile: Vector2i, height: float = 0.0) -> Vector3:
	return absolute_to_world(tile_origin_absolute(tile), height)
