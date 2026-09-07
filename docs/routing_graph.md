# BRG1 routing graph

`tools/build_routing.py` compiles movement-relevant OSM ways into a compact directed graph for gameplay. Godot/runtime does not parse the source PBF.

The graph keeps both physical directions of every segment. Legal one-way direction is represented by the absence/presence of the `against_oneway` flag, so normal routing can reject illegal travel while pursuit/getaway profiles can deliberately allow it later. Restricted roads, cycleways, footways and paths remain in the graph; access policy decides whether a profile may use them.

Speeds are normalized to km/h. Numeric OSM `maxspeed` values are used directly, explicit `mph`/`knot(s)` values are converted, and missing/unusable values use the small fallback table in `routing_graph.py`. `routing_stats.json` records explicit/fallback counts, fallback counts by highway type and unknown raw values so the fallback policy can be reviewed against Sweden data.

Distances are stored as geodesic metres. Web Mercator coordinates are stored only for snapping/debug/world placement and are not routing distance truth.

## BRG1 layout

Header: magic `BRG1`, node count, directed edge count.

Each node stores OSM node id, lon/lat, projected x/y and a contiguous adjacency offset/count into the edge table.

Each edge stores OSM way id, source segment index, source/target node-table indexes, true length, speed, highway class, access class/reason, direction/bridge/tunnel flags, speed source and OSM layer. The stable edge identity is derived deterministically from source way id, source/target OSM node ids and segment index; it does not depend on export order.

## Build and test

Build only routing data:

```bash
python tools/build_routing.py /path/to/sweden.osm.pbf --output world_data
```

The normal Sweden build also runs the routing compiler.

Run all routing correctness tests headlessly:

```bash
python -m unittest discover -s tests -v
```

The end-to-end test uses a tiny `.osm` fixture and verifies `OSM -> builder -> BRG1 -> loader` without requiring a rendered Godot scene. Production `.osm.pbf` reading uses `pyosmium`.
