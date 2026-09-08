# Local music assets

Place locally exported game music in this directory and register each track with `MusicPlayer` using a stable id, title, and `res://assets/music/...` asset path.

The music subsystem does not require Suno, streaming services, or runtime internet access. Track metadata is data-driven; adding a song does not require changing playback implementation code.
