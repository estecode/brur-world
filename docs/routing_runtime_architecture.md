# Routing runtime architecture

This document defines the performance contract for Brur World's production road router.

## Runtime goals

- Road snapping: < 0.2 ms
- City route: < 1 ms
- ~350 km route: < 5 ms
- Whole-Sweden route: < 15 ms
- No heap allocation in the query loop.
- No runtime graph preprocessing.
- Pointer-free binary data with explicit little-endian integer fields.
- C++20 core with no third-party or OS-specific API dependency.
- Godot, desktop, console and WASM adapters provide only a read-only byte buffer and query inputs.

## Data ownership

`BRG1` remains the exact source routing graph and correctness reference. Runtime acceleration data is generated offline and stored in separate sidecars.

- Snap sidecar: fixed-grid CSR over physical road segments, mapping directly to BRG edge/fraction candidates.
- CH sidecars: contraction hierarchy topology plus metric weights and shortcut decomposition.
- Search index: address/POI search remains separate from routing acceleration.

Rendering data is not part of the routing core and must not be changed by routing optimizations.

## Hot-path layout

The query path uses structure-of-arrays / CSR data where practical. Hot CH relaxation data should contain only the fields needed to advance search, ideally 32-bit target and 32-bit weight. Shortcut decomposition and other cold data stay in separate arrays and are read only after a route has been found.

Binary formats must not serialize native C++ structs. All fields have explicit widths, byte order and offsets. Runtime APIs consume a read-only byte span rather than assuming `mmap`; platform adapters may back that span with mmap, a console file buffer or WASM memory.

## Query workspace

Each worker owns a preallocated `RoutingContext`. The query loop performs no malloc/new and no container growth.

Search state must be sparse/fixed-capacity rather than full graph-sized `distance[]`, `parent[]` and `epoch[]` arrays per worker. A fixed open-addressed state table is preferred. Overflow is a benchmark failure and must be reported rather than silently allocating.

Priority queues are fixed-capacity. Both a monotonic radix heap and a binary heap may be benchmarked behind the same interface; the production choice is based on measured route latency and bytes touched, not asymptotic complexity alone.

## Turn restrictions

Turn restrictions are normalized offline before contraction. A restriction that depends on the incoming edge cannot be represented as a simple node flag. Restricted junctions therefore use edge/turn state (or an equivalent compact automaton for via-way restrictions) so CH shortcuts can only represent legal paths.

The whole graph must not be blindly expanded to a full edge-based graph if a compact hybrid representation can preserve exact legality. Expansion size and shortcut growth are mandatory build statistics.

## Coordinates and snapping

The snap index stores road-segment references, never only road-node references. Grid buckets are flat CSR arrays (`cell_offsets[]`, `segment_refs[]`) and are generated offline.

Grid cell size is a benchmarked parameter; 256 m is the initial Sweden candidate instead of kilometre-scale buckets. The benchmark must report candidate counts as well as latency.

Production snap coordinates should be local fixed-point `int32` values (centimetres are sufficient for Sweden) to avoid global float precision loss and to provide deterministic cross-platform arithmetic. Render/Web-Mercator coordinates remain a separate concern. Switching the existing world projection requires an explicit compatibility migration because current render and road data share that coordinate space.

## Benchmarks

Every Sweden routing benchmark reports at least:

- map/open latency for every sidecar,
- snapping latency and candidate count,
- route latency,
- settled nodes,
- relaxed edges,
- queue peak,
- sparse-state peak,
- shortcut count/unpack count,
- route distance and travel time.

A fast wall-clock result with a large search space is not accepted as proof of the architecture; the search-space counters must also remain small.
