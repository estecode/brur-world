# Continuous world showcase POC #126

This harness demonstrates one continuous BRUR world from a 30 km map view into local 3D and the existing Manual Drive camera.

It composes production systems rather than reimplementing them:

- `scenes/main.tscn` for the normal map/camera/sun/world runtime,
- `BuildingStreamLayer` / `BuildingMeshBuilder` for promoted batched building streaming,
- `WorldCoordinates` for all projected/world/tile conversion,
- `WorldAtmosphere` for altitude-driven haze/depth presentation,
- the existing production player vehicle and Manual Drive camera.

The Safe Check prepares `.poc_runtime/world_showcase/` only from already-built runtime data. Buildings come from `world_data/buildings.jsonl`; the visible map comes from 50 km local extracts of the existing `world_data/background.brmap`. It does **not** read the Sweden PBF or rebuild authoritative world data.

The local objective hook is fail-closed across supported Godot versions: script parse/compile/runtime-test errors make the Safe Check fail instead of allowing the visual harness to open on a broken revision.

## Performance profile

The first real-machine iterations were not testable: about 6 FPS, then 1–4 FPS after building-only reductions. The earlier runtime log showed the full Sweden BRM2 background contributing more than 3.3 million triangles and POI streaming reaching tens of thousands of visible markers.

For this POC only:

- only the current demo city's 50 km local BRM2 map extract is loaded,
- POI presentation/refresh is disabled because POIs are outside #126's acceptance target,
- full-detail buildings stay local to roughly 1.5 km,
- building streaming stays on the local world tile with no directional prefetch,
- building and directional dynamic shadows remain disabled.

The visual/data source is still the same BRUR runtime world; this is a smaller presentation working set, not a fake replacement map.

## Human flow

1. Start at Malmö around 30 km altitude.
2. Press **Cinematic dive: 30 km → 1.4 km** and watch the map tilt progressively while buildings rise into the same world.
3. Judge haze, building variation and frame pacing as the city resolves.
4. Below 5 km press **Manual Drive** and verify the existing chase-camera handoff feels continuous.
5. Press **Return from drive to map world** to leave driving without restarting the scene.
6. Run **Stress: Malmö → Göteborg → Stockholm → Malmö** and watch streaming metrics while old city geometry and local map presentation are replaced.

Performance acceptance on the project-leader machine is at least 30 FPS during normal showcase use, with 100+ FPS preferred.

The branch startup override, disposable cache preparation and branch-specific local PR check are experiment-only and must not be promoted unchanged to `main`.
