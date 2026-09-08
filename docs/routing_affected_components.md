# Routing performance migration: affected components

This migration is intentionally isolated from rendering and gameplay systems.

## Directly affected

- `tools/gps_snap_index.py`
  - smaller benchmarked fixed grid,
  - segment candidate accounting,
  - future fixed-point snap geometry format.
- `tools/build_snap_index.py`
  - offline generation of the snap sidecar.
- `tools/gps_ch.py`
  - correctness reference for hierarchy routing,
  - to be replaced/extended by scalable CH preprocessing and packed runtime output.
- `tools/gps_bidirectional.py`
  - remains the exact non-CH fallback/reference router and witness-search reference.
- `tools/gps_incoming_index.py`
  - useful for reference/witness work; production CH queries should not need full reverse BRG adjacency.
- `tools/benchmark_gps.py`
  - must measure candidate counts, settled nodes, relaxed edges, queue peak and state-table peak in addition to latency.
- routing tests
  - CH must match exact routing for legality/cost,
  - turn restrictions and via-way restrictions need dedicated fixtures,
  - binary readers/writers need deterministic cross-platform layout tests.

## Offline routing compiler changes required next

- Parse OSM turn restrictions before hierarchy preprocessing.
- Normalize restrictions into compact turn state / automata.
- Build scalable contraction ordering and witness search.
- Emit explicit little-endian packed CH topology, metric weights and shortcut decomposition sidecars.
- Emit build statistics for turn-state expansion and shortcut growth.

## Coordinate migration

The current world uses Web Mercator coordinates for render placement and routing-side projected coordinates. Production snapping should use local fixed-point metric coordinates, but that migration must be isolated so the visible map remains unchanged.

Preferred approach: add a routing/snap-only metric coordinate stream first. Do not change road rendering tiles or Godot world coordinates as part of the routing optimization.

## Runtime integration affected later

- A small C++20 routing core / Godot GDExtension adapter will consume read-only byte buffers.
- `scripts/main.gd` should only call the routing service; CH/search logic must not be added to the main Godot script.
- WASM/console/desktop adapters own file/buffer acquisition. The core does not call mmap or platform APIs.

## Explicitly unaffected

- Road rendering geometry and visual LOD.
- Background/map tiles.
- Traffic simulation.
- Police logic.
- Player vehicle movement.
- POI marker visibility rules.
- Address/POI search semantics except for the final step that snaps a chosen search result onto the routing graph.
