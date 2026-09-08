#!/usr/bin/env python3
"""Build the persistent BRI1 reverse-adjacency index for GPS routing.

Dependencies:
- routing_graph_view.py memory-maps BRG1.
- gps_incoming_index.py performs the offline index build.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from gps_incoming_index import build_incoming_index
from routing_graph_view import RoutingGraphView


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("graph", type=Path, nargs="?", default=Path("world_data/routing.brg"))
    parser.add_argument("--output", type=Path, default=Path("world_data/routing_incoming.bri"))
    args = parser.parse_args()

    try:
        with RoutingGraphView(args.graph) as graph:
            build_incoming_index(graph, args.output)
    except KeyboardInterrupt:
        print("\n[incoming-index] Build interrupted; existing index was left untouched.", flush=True)
        raise SystemExit(130)


if __name__ == "__main__":
    main()
