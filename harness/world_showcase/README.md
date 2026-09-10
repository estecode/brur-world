# Continuous world showcase POC #126

This harness demonstrates one continuous BRUR world from a 30 km map view into local 3D and the existing Manual Drive camera.

It composes production systems rather than reimplementing them:

- `scenes/main.tscn` for the normal Sweden map, roads, water/land background, camera, clouds, world clock and astronomical sun,
- `BuildingStreamLayer` / `BuildingMeshBuilder` for promoted batched building streaming,
- `WorldCoordinates` for all projected/world/tile conversion,
- `WorldAtmosphere` for altitude-driven haze/depth presentation,
- the existing production player vehicle and Manual Drive camera.

The Safe Check prepares `.poc_runtime/world_showcase/` only from the already-built `world_data/buildings.jsonl`. It does **not** read the Sweden PBF or rebuild authoritative world data.

The local objective hook is fail-closed across supported Godot versions: script parse/compile/runtime-test errors make the Safe Check fail instead of allowing the visual harness to open on a broken revision.

## Performance profile

The showcase intentionally keeps full-detail extruded buildings local to roughly 1.5 km around Malmö, Göteborg and Stockholm, disables building shadow casting and dynamic directional shadows, and streams only the local world tile. This keeps the POC useful for evaluating the continuous map-to-street experience without attempting to render city-scale full-detail geometry unnecessarily.

## Human flow

1. Start at Malmö around 30 km altitude.
2. Press **Cinematic dive: 30 km → 1.4 km** and watch the map tilt progressively while buildings rise into the same world.
3. Judge haze, building variation and frame pacing as the city resolves.
4. Below 5 km press **Manual Drive** and verify the existing chase-camera handoff feels continuous.
5. Press **Return from drive to map world** to leave driving without restarting the scene.
6. Run **Stress: Malmö → Göteborg → Stockholm → Malmö** and watch streaming metrics while old city geometry unloads.

Performance acceptance on the project-leader machine is at least 30 FPS during normal showcase use, with 100+ FPS preferred.

The branch startup override, disposable cache preparation and branch-specific local PR check are experiment-only and must not be promoted unchanged to `main`.
