extends RefCounted
class_name MusicLibrary

## Stores data-driven local music track metadata for the music subsystem.
## Dependencies: Godot core containers only; does not depend on audio playback, UI, or gameplay.

var _tracks: Array[Dictionary] = []
var _index_by_id: Dictionary = {}

func add_track(track: Dictionary) -> bool:
	var normalized := _normalize_track(track)
	if normalized.is_empty():
		return false
	var track_id := str(normalized["id"])
	if _index_by_id.has(track_id):
		return false
	_index_by_id[track_id] = _tracks.size()
	_tracks.append(normalized)
	return true

func add_tracks(tracks: Array) -> int:
	var added := 0
	for track in tracks:
		if track is Dictionary and add_track(track):
			added += 1
	return added

func count() -> int:
	return _tracks.size()

func is_empty() -> bool:
	return _tracks.is_empty()

func has_track(track_id: String) -> bool:
	return _index_by_id.has(track_id)

func track(track_id: String) -> Dictionary:
	if not _index_by_id.has(track_id):
		return {}
	return _tracks[int(_index_by_id[track_id])].duplicate(true)

func track_at(index: int) -> Dictionary:
	if index < 0 or index >= _tracks.size():
		return {}
	return _tracks[index].duplicate(true)

func track_id_at(index: int) -> String:
	var item := track_at(index)
	return str(item.get("id", ""))

func all_tracks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in _tracks:
		result.append(item.duplicate(true))
	return result

func _normalize_track(track: Dictionary) -> Dictionary:
	var track_id := str(track.get("id", "")).strip_edges()
	var title := str(track.get("title", "")).strip_edges()
	var asset_path := str(track.get("asset_path", "")).strip_edges()
	if track_id.is_empty() or title.is_empty() or asset_path.is_empty():
		return {}
	if not asset_path.begins_with("res://"):
		return {}
	return {
		"id": track_id,
		"title": title,
		"artist": str(track.get("artist", "")).strip_edges(),
		"asset_path": asset_path,
		"tags": track.get("tags", []).duplicate(true) if track.get("tags", []) is Array else [],
	}
