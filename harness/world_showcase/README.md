# Continuous world showcase POC #126

This harness demonstrates one continuous BRUR world from a 30 km map view into local 3D and the existing Manual Drive camera.

It composes production systems rather than reimplementing them:

- `scenes/main.tscn` for the normal Sweden map, roads, water/land background, camera, clouds, world clock and astronomical sun,
- `BuildingStreamLayer` / `BuildingMeshBuilder` for promoted batched building streaming,
- `WorldCoordinates` for all projected/world/tile conversion,
- `WorldAtmosphere` for altitude-driven haze/depth presentation,
- the existing production player vehicle and Manual Drive camera.

The Safe Check prepares `.poc_runtime/world_showcase/` only from the already-built `world_data/buildings.jsonl`. It does **not** read the Sweden PBF or rebuild authoritative world data.

## Performance-first budget

The fully extruded building working set is limited to a 1.5 km radius around each demo city center. The earlier 7.5 km radius placed an unnecessarily large city-wide mesh into one coarse world tile and measured about 6 FPS on the project leader's Mac. The POC needs to prove the continuous map-to-street experience, not render hundreds of square kilometres of full-detail buildings at once.

Dynamic building/directional shadows are disabled by default in the showcase. Depth still comes from normals, deterministic roof/wall/base tones, haze and the existing astronomical light direction. Proper distance-based shadow LOD can be promoted later once production presentation cells are finer than the coarse world tile.

The target for this POC is **at least 30 FPS on the project leader's test machine**, with **100 FPS or better preferred**.

## Human flow

1. Start at Malmö around 30 km altitude.
2. Press **Cinematic dive: 30 km → 1.4 km** and watch the map tilt progressively while buildings rise into the same world.
3. Judge haze, building variation and frame pacing as the city resolves.
4. Below 5 km press **Manual Drive** and verify the existing chase-camera handoff feels continuous.
5. Press **Return from drive to map world** to leave driving without restarting the scene.
6. Run **Stress: Malmö → Göteborg → Stockholm → Malmö** and watch streaming metrics while old city geometry unloads.

The branch startup override, disposable cache preparation and branch-specific local PR check are experiment-only and must not be promoted unchanged to `main`.
