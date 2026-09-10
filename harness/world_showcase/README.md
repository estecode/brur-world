# Continuous world showcase POC #126

This harness demonstrates one continuous BRUR world from a 30 km map view into local 3D and the existing Manual Drive camera.

It composes production systems rather than reimplementing them:

- `scenes/main.tscn` for the normal Sweden map, roads, water/land background, camera, clouds, world clock and astronomical sun,
- `BuildingStreamLayer` / `BuildingMeshBuilder` for promoted batched building streaming,
- `WorldCoordinates` for all projected/world/tile conversion,
- `WorldAtmosphere` for altitude-driven haze/depth presentation,
- the existing production player vehicle and Manual Drive camera.

The Safe Check prepares `.poc_runtime/world_showcase/` only from the already-built `world_data/buildings.jsonl`. It does **not** read the Sweden PBF or rebuild authoritative world data.

## Human flow

1. Start at Malmö around 30 km altitude.
2. Press **Cinematic dive: 30 km → 1.4 km** and watch the map tilt progressively while buildings rise into the same world.
3. Judge haze, shadows, building variation and frame pacing as the city resolves.
4. Below 5 km press **Manual Drive** and verify the existing chase-camera handoff feels continuous.
5. Press **Return from drive to map world** to leave driving without restarting the scene.
6. Run **Stress: Malmö → Göteborg → Stockholm → Malmö** and watch streaming metrics while old city geometry unloads.

The branch startup override, disposable cache preparation and branch-specific local PR check are experiment-only and must not be promoted unchanged to `main`.
