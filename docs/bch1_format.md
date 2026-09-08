# BCH1 contraction-hierarchy sidecar

`BCH1` is Brur World's first portable binary correctness checkpoint for contraction-hierarchy routing.

It is generated offline from the exact BRG1 routing graph and loaded read-only at runtime. BRG1 remains the source of truth for original road topology, metric distance, speed and route-step identity.

## Goals

- pointer-free binary data
- explicit little-endian fields
- mmap/read-only-byte-span friendly layout
- no expansion into per-edge Python/runtime objects when loaded
- CSR adjacency for the hot forward/backward CH search
- shortcut decomposition kept in the edge table for cold post-query unpacking
- exact metric-specific routing semantics matching `GraphRouter`

`BCH1` is not yet the final Sweden production encoding. The first version deliberately stores CH edge cost as IEEE-754 float64 so serialization/query correctness can be proven without quantization differences. A later measured format may replace this with compact integer/fixed-point weights.

## Header

All integer fields are unsigned unless noted otherwise.

| Field | Type | Meaning |
| --- | --- | --- |
| magic | 4 bytes | `BCH1` |
| version | uint32 | format version, currently `1` |
| node_count | uint32 | BRG/CH node count |
| edge_count | uint32 | original CH edges + shortcuts |
| upward_ref_count | uint32 | number of forward CSR edge references |
| downward_ref_count | uint32 | number of backward CSR edge references |
| preference_code | uint32 | metric/routing preference |
| reserved | uint32 | zero |
| avoid_penalty | float32 | metric penalty parameter |
| rank_offset | uint64 | byte offset to rank array |
| edge_offset | uint64 | byte offset to CH edge table |
| upward_offsets_offset | uint64 | byte offset to forward CSR offsets |
| upward_refs_offset | uint64 | byte offset to forward CSR edge refs |
| downward_offsets_offset | uint64 | byte offset to backward CSR offsets |
| downward_refs_offset | uint64 | byte offset to backward CSR edge refs |

The loader validates every expected offset and the exact file size. A malformed/truncated sidecar is rejected instead of being partially interpreted.

## Rank array

`node_count` × uint32 contraction ranks.

The rank array is retained as topology metadata even though the first mmap query consumes the already-built CSR traversal lists directly.

## CH edge table

Each edge record is:

| Field | Type | Meaning |
| --- | --- | --- |
| source_index | uint32 | source CH/BRG node |
| target_index | uint32 | target CH/BRG node |
| cost | float64 | metric-specific CH edge cost |
| original_edge_index | int32 | BRG edge index, or `-1` for shortcut |
| left_child | int32 | first child CH edge for shortcut, else `-1` |
| right_child | int32 | second child CH edge for shortcut, else `-1` |

Shortcut children recursively unpack to original BRG edge indices only after the route has been found.

## Forward CSR

`node_count + 1` uint32 offsets followed by `upward_ref_count` uint32 CH-edge indices.

These are edges whose source rank is lower than target rank and are traversed by the forward CH search.

## Backward CSR

`node_count + 1` uint32 offsets followed by `downward_ref_count` uint32 CH-edge indices.

These reference downward original-direction edges by their lower-rank target node. Backward search walks them in reverse toward their source.

## Metric identity

A BCH1 file represents exactly one metric customization. Runtime routing rejects a request whose routing preference or avoidance penalty does not match the sidecar.

The same BRG1 graph is still shared by all routing preferences; separate BCH1 weight/customization sidecars are acceleration data, not separate road graphs.

## Current checkpoint vs production

Implemented now:

- binary serialization from the exact fixture-scale CH correctness model
- mmap loader/query without materializing CH records as runtime objects
- exact shortcut unpacking to BRG1 route steps
- all-pairs fixture tests against `GraphRouter` for fastest, shortest and both avoidance modes

Still required before Sweden preprocessing:

- scalable Sweden ordering/topology builder
- scalable metric customization
- fixed-capacity query workspace and priority queue
- measured 32-bit/fixed-point weight representation if it preserves required accuracy
- Sweden build statistics for shortcut growth, bytes, preprocessing time and query search-space counters

Do not use the fixture-scale `gps_ch.build_ch()` witness-search builder on the full Sweden graph.
