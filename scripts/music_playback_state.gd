extends RefCounted
class_name MusicPlaybackState

## Owns deterministic playlist selection and playback state without producing audio.
## Dependencies: MusicLibrary and Godot RandomNumberGenerator only; does not depend on SceneTree, audio, UI, or gameplay.

const MIN_VOLUME := 0.0
const MAX_VOLUME := 1.0

var _library: MusicLibrary
var _current_index := -1
var _is_playing := false
var _is_paused := false
var _shuffle_enabled := false
var _repeat_enabled := false
var _volume := 1.0
var _rng := RandomNumberGenerator.new()

func _init(library: MusicLibrary, shuffle_seed: int = 1) -> void:
	_library = library
	_rng.seed = shuffle_seed

func play(track_id: String = "") -> bool:
	if _library == null or _library.is_empty():
		return false
	if not track_id.is_empty():
		var found := _find_index(track_id)
		if found < 0:
			return false
		_current_index = found
	elif _current_index < 0:
		_current_index = 0
	_is_playing = true
	_is_paused = false
	return true

func pause() -> bool:
	if not _is_playing or _is_paused:
		return false
	_is_paused = true
	return true

func resume() -> bool:
	if not _is_playing or not _is_paused:
		return false
	_is_paused = false
	return true

func stop() -> void:
	_is_playing = false
	_is_paused = false

func next() -> bool:
	return _move(1)

func previous() -> bool:
	return _move(-1)

func advance_after_finished() -> bool:
	if _library == null or _library.is_empty():
		stop()
		return false
	if _repeat_enabled and _current_index >= 0:
		_is_playing = true
		_is_paused = false
		return true
	return next()

func set_shuffle_enabled(enabled: bool) -> void:
	_shuffle_enabled = enabled

func shuffle_enabled() -> bool:
	return _shuffle_enabled

func set_repeat_enabled(enabled: bool) -> void:
	_repeat_enabled = enabled

func repeat_enabled() -> bool:
	return _repeat_enabled

func set_volume(value: float) -> void:
	_volume = clampf(value, MIN_VOLUME, MAX_VOLUME)

func volume() -> float:
	return _volume

func is_playing() -> bool:
	return _is_playing

func is_paused() -> bool:
	return _is_paused

func current_track_id() -> String:
	if _library == null or _current_index < 0:
		return ""
	return _library.track_id_at(_current_index)

func current_track() -> Dictionary:
	if _library == null or _current_index < 0:
		return {}
	return _library.track_at(_current_index)

func _move(direction: int) -> bool:
	if _library == null or _library.is_empty():
		stop()
		return false
	if _current_index < 0:
		_current_index = 0
	elif _shuffle_enabled and _library.count() > 1:
		var candidate := _current_index
		while candidate == _current_index:
			candidate = _rng.randi_range(0, _library.count() - 1)
		_current_index = candidate
	else:
		_current_index = posmod(_current_index + direction, _library.count())
	_is_playing = true
	_is_paused = false
	return true

func _find_index(track_id: String) -> int:
	for index in range(_library.count()):
		if _library.track_id_at(index) == track_id:
			return index
	return -1
