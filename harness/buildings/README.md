# Malmö 3D buildings POC

This harness is the isolated visual proof of concept for issue #120.

It reuses the production BRUR map renderer, camera, shared world coordinates and player vehicle. Building geometry comes only from the existing ignored `world_data/buildings.jsonl` runtime export. The Safe Check creates a disposable `.poc_runtime/buildings/` Malmö tile cache from that file; it does **not** read the Sweden PBF and does **not** rebuild or replace roads, routing, search, POIs, background map data or the building source export.

The building presentation intentionally stays simple: real OSM footprints are extruded into gray volumes, batched to one mesh per loaded world tile and streamed only around the camera. Buildings are absent at high map altitude and ease into full height as the camera descends.

The issue branch points `project.godot` at this harness so the PR Safe Check opens the POC directly. That startup override and the PR-owned check hook are experiment-only and should not be promoted to `main` unchanged.

## Human check

Use the PR's `▶ Run safe check` link. Start over Malmö, zoom from the detailed map down through the building transition, then below 5 km use **Manual Drive**. Judge frame smoothness, hard popping, city readability and the camera handoff behind the car. Objective geometry/streaming contracts run headlessly before Godot opens.
