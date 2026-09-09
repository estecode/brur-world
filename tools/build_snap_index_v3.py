#!/usr/bin/env python3
"""Build the fixed-point BRS3 road snap sidecar from an existing BRG1 graph.

Dependencies:
- routing_graph_view memory-maps BRG1 without expanding Sweden into Python objects.
- gps_snap_index_v3 owns the portable fixed-point segment-grid format.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from gps_snap_index_v3 import DEFAULT_CELL_SIZE_M, build_snap_index_v3
from routing_graph_view import RoutingGraphView


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("graph", type=Path, nargs="?", default=Path("world_data/routing.brg"))
    parser.add_argument("--output", type=Path, default=Path("world_data/routing_snap_v3.brs"))
    parser.add_argument("--cell-size", type=float, default=DEFAULT_CELL_SIZE_M)
    args = parser.parse_args()

    print(f"[snap-v3] source: {args.graph}", flush=True)
    with RoutingGraphView(args.graph) as graph:
        print(
            f"[snap-v3] graph: {len(graph.nodes):,} nodes, {len(graph.edges):,} directed edges",
            flush=True,
        )
        build_snap_index_v3(graph, args.output, args.cell_size)


if __name__ == "__main__":
    main()
