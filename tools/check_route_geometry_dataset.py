#!/usr/bin/env python3
"""Headlessly verify BRG1 and BRH1 describe the same detailed directed road geometry.

Dependencies:
- Reads existing routing.brg and routing_geometry.brh only.
- Uses route_geometry.py for the structural/data invariant checks.
- Intended for production-data validation before any Godot playtest.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from route_geometry import validate_route_geometry_alignment


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("world_data", type=Path, help="Directory containing routing.brg and routing_geometry.brh")
    args = parser.parse_args()

    world_data = args.world_data.resolve()
    graph_path = world_data / "routing.brg"
    geometry_path = world_data / "routing_geometry.brh"
    if not graph_path.is_file():
        raise SystemExit(f"missing routing graph: {graph_path}")
    if not geometry_path.is_file():
        raise SystemExit(f"missing route geometry: {geometry_path}")

    def progress(processed: int, total: int) -> None:
        print(f"[route-geometry-check] {processed:,}/{total:,} directed edges", flush=True)

    report = validate_route_geometry_alignment(
        graph_path,
        geometry_path,
        progress=progress,
    )
    print(
        "[route-geometry-check] OK | "
        f"edges={int(report['edge_count']):,} | "
        f"physical_shapes={int(report['physical_shape_count']):,} | "
        f"points={int(report['point_count']):,} | "
        f"max_endpoint_error={float(report['max_endpoint_error_m']):.3f}m | "
        f"max_length_error={float(report['max_length_error_m']):.3f}m",
        flush=True,
    )


if __name__ == "__main__":
    main()
