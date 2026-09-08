extends SceneTree

## Headless deterministic tests for the reusable music library, playback state, and Godot audio adapter.
## Dependencies: scripts/music_library.gd, scripts/music_playback_state.gd, scripts/music_player.gd, and a local AudioStreamWAV fixture.

const MusicLibraryScript = preload("res://scripts/music_library.gd")
const MusicPlaybackStateScript = preload("res://scripts/music_playback_state.gd")
const MusicPlayerScript = preload("res://scripts/music_player.gd")
const FIXTURE_STREAM := "res://tests/fixtures/music_test_stream.tres"

func _init() -> void:
	_test_library()
	_test_empty_library_playback()
	_test_one_track_library()
	_test_playback()
	_test_shuffle_determinism()
	_test_adapter_playback()
	print("godot music playback-state tests: OK")
	quit(0)

func _fixture_library():
	var library = MusicLibraryScript.new()
	_assert(library.add_track({"id": "one", "title": "One", "artist": "Test", "asset_path": "res://assets/music/one.ogg"}), "first track is accepted")
	_assert(library.add_track({"id": "two", "title": "Two", "asset_path": "res://assets/music/two.ogg"}), "second track is accepted")
	_assert(library.add_track({"id": "three", "title": "Three", "asset_path": "res://assets/music/three.ogg"}), "third track is accepted")
	return library

func _test_library() -> void:
	var library = MusicLibraryScript.new()
	_assert(library.is_empty(), "library starts empty")
	_assert(not library.add_track({"id": "bad", "title": "Bad"}), "missing asset path is rejected")
	_assert(not library.add_track({"id": "bad2", "title": "Bad", "asset_path": "/tmp/song.ogg"}), "non-resource asset path is rejected")
	_assert(library.add_track({"id": "one", "title": "One", "asset_path": "res://assets/music/one.ogg", "tags": ["test"]}), "valid track is accepted")
	_assert(not library.add_track({"id": "one", "title": "Duplicate", "asset_path": "res://assets/music/duplicate.ogg"}), "duplicate id is rejected")
	_assert(library.count() == 1, "duplicate does not mutate library")
	var copy := library.track("one")
	copy["title"] = "Mutated"
	_assert(str(library.track("one")["title"]) == "One", "returned metadata cannot mutate library")

func _test_empty_library_playback() -> void:
	var library = MusicLibraryScript.new()
	var state = MusicPlaybackStateScript.new(library, 7)
	_assert(not state.play(), "empty library cannot start playback")
	_assert(not state.next(), "empty library next fails cleanly")
	_assert(not state.previous(), "empty library previous fails cleanly")
	_assert(not state.advance_after_finished(), "empty library finish handling fails cleanly")
	_assert(state.current_track_id().is_empty(), "empty library keeps no current track")
	_assert(not state.is_playing() and not state.is_paused(), "empty library remains stopped")

func _test_one_track_library() -> void:
	var library = MusicLibraryScript.new()
	_assert(library.add_track({"id": "solo", "title": "Solo", "asset_path": "res://assets/music/solo.ogg"}), "single track is accepted")
	var state = MusicPlaybackStateScript.new(library, 9)
	_assert(state.play(), "single-track library starts")
	_assert(state.current_track_id() == "solo", "single-track play selects its only track")
	_assert(state.next() and state.current_track_id() == "solo", "single-track next wraps to itself")
	_assert(state.previous() and state.current_track_id() == "solo", "single-track previous wraps to itself")
	state.set_shuffle_enabled(true)
	_assert(state.next() and state.current_track_id() == "solo", "single-track shuffle remains on valid track")
	state.set_repeat_enabled(true)
	_assert(state.advance_after_finished() and state.current_track_id() == "solo", "single-track repeat restarts itself")

func _test_playback() -> void:
	var library = _fixture_library()
	var state = MusicPlaybackStateScript.new(library, 42)
	_assert(state.current_track_id().is_empty(), "no current track initially")
	_assert(not state.play("missing"), "invalid track id fails cleanly")
	_assert(state.play(), "play starts first track")
	_assert(state.current_track_id() == "one", "default play selects first track")
	_assert(state.is_playing() and not state.is_paused(), "play state is active")
	_assert(state.pause(), "pause succeeds")
	_assert(state.is_paused(), "pause state is exposed")
	_assert(state.resume(), "resume succeeds")
	_assert(not state.is_paused(), "resume clears pause")
	_assert(state.next() and state.current_track_id() == "two", "next follows library order")
	_assert(state.previous() and state.current_track_id() == "one", "previous follows library order")
	_assert(state.previous() and state.current_track_id() == "three", "previous wraps")
	state.set_repeat_enabled(true)
	_assert(state.advance_after_finished(), "repeat restarts current track")
	_assert(state.current_track_id() == "three", "repeat does not change track")
	state.set_repeat_enabled(false)
	_assert(state.advance_after_finished(), "finished advances when repeat is off")
	_assert(state.current_track_id() == "one", "finished wraps to next track")
	state.set_volume(2.0)
	_assert(is_equal_approx(state.volume(), 1.0), "volume clamps high")
	state.set_volume(-1.0)
	_assert(is_equal_approx(state.volume(), 0.0), "volume clamps low")
	state.stop()
	_assert(not state.is_playing() and not state.is_paused(), "stop clears playback state")

func _test_shuffle_determinism() -> void:
	var first = MusicPlaybackStateScript.new(_fixture_library(), 12345)
	var second = MusicPlaybackStateScript.new(_fixture_library(), 12345)
	first.set_shuffle_enabled(true)
	second.set_shuffle_enabled(true)
	_assert(first.play() and second.play(), "shuffle fixtures start")
	var first_sequence: Array[String] = []
	var second_sequence: Array[String] = []
	for _step in range(8):
		_assert(first.next() and second.next(), "shuffle next succeeds")
		first_sequence.append(first.current_track_id())
		second_sequence.append(second.current_track_id())
	_assert(first_sequence == second_sequence, "same seed produces same shuffle sequence")
	for track_id in first_sequence:
		_assert(track_id in ["one", "two", "three"], "shuffle selects only valid tracks")

func _test_adapter_playback() -> void:
	var player = MusicPlayerScript.new()
	root.add_child(player)
	_assert(player.add_track({"id": "fixture", "title": "Fixture", "asset_path": FIXTURE_STREAM}), "adapter accepts local fixture track")
	_assert(player.play("fixture"), "adapter loads and starts a local AudioStream")
	_assert(player.current_track_id() == "fixture", "adapter exposes current track")
	_assert(player.is_playing() and not player.is_paused(), "adapter exposes active playback state")
	_assert(player.pause() and player.is_paused(), "adapter pauses playback")
	_assert(player.resume() and not player.is_paused(), "adapter resumes playback")
	player.set_volume(0.25)
	_assert(is_equal_approx(player.volume(), 0.25), "adapter exposes volume state")
	player.stop()
	_assert(not player.is_playing(), "adapter stops playback")
	player.free()

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("music playback-state test failed: " + message)
	quit(1)
