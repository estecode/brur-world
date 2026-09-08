extends Node
class_name MusicPlayer

## Adapts MusicLibrary/MusicPlaybackState to Godot AudioStreamPlayer playback.
## Dependencies: MusicLibrary, MusicPlaybackState, and Godot AudioStreamPlayer; UI/gameplay may call its public API but are not dependencies.

signal track_changed(track: Dictionary)
signal playback_changed(is_playing: bool, is_paused: bool)

var _library := MusicLibrary.new()
var _state := MusicPlaybackState.new(_library)
var _audio := AudioStreamPlayer.new()

func _ready() -> void:
	add_child(_audio)
	_audio.finished.connect(_on_audio_finished)
	_apply_volume()

func add_track(track: Dictionary) -> bool:
	return _library.add_track(track)

func add_tracks(tracks: Array) -> int:
	return _library.add_tracks(tracks)

func play(track_id: String = "") -> bool:
	if not _state.play(track_id):
		return false
	return _start_current_track()

func pause() -> bool:
	if not _state.pause():
		return false
	_audio.stream_paused = true
	playback_changed.emit(true, true)
	return true

func resume() -> bool:
	if not _state.resume():
		return false
	_audio.stream_paused = false
	playback_changed.emit(true, false)
	return true

func stop() -> void:
	_state.stop()
	_audio.stop()
	_audio.stream_paused = false
	playback_changed.emit(false, false)

func next() -> bool:
	if not _state.next():
		return false
	return _start_current_track()

func previous() -> bool:
	if not _state.previous():
		return false
	return _start_current_track()

func set_shuffle_enabled(enabled: bool) -> void:
	_state.set_shuffle_enabled(enabled)

func shuffle_enabled() -> bool:
	return _state.shuffle_enabled()

func set_repeat_enabled(enabled: bool) -> void:
	_state.set_repeat_enabled(enabled)

func repeat_enabled() -> bool:
	return _state.repeat_enabled()

func set_volume(value: float) -> void:
	_state.set_volume(value)
	_apply_volume()

func volume() -> float:
	return _state.volume()

func current_track() -> Dictionary:
	return _state.current_track()

func current_track_id() -> String:
	return _state.current_track_id()

func is_playing() -> bool:
	return _state.is_playing()

func is_paused() -> bool:
	return _state.is_paused()

func _start_current_track() -> bool:
	var track := _state.current_track()
	var asset_path := str(track.get("asset_path", ""))
	if asset_path.is_empty():
		_state.stop()
		return false
	var stream := load(asset_path) as AudioStream
	if stream == null:
		_state.stop()
		push_warning("MusicPlayer could not load track: %s" % asset_path)
		return false
	_audio.stream = stream
	_audio.stream_paused = false
	_audio.play()
	track_changed.emit(track)
	playback_changed.emit(true, false)
	return true

func _on_audio_finished() -> void:
	if not _state.advance_after_finished():
		playback_changed.emit(false, false)
		return
	_start_current_track()

func _apply_volume() -> void:
	if _state.volume() <= 0.0:
		_audio.volume_db = -80.0
	else:
		_audio.volume_db = linear_to_db(_state.volume())
