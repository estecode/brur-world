#!/usr/bin/env python3
"""Build and publish the version-bound routing runtime dataset.

Dependencies:
- build_routing.py produces BRG1 graph and BRH1 route geometry from one OSM source.
- gps_snap_index.py produces BRS2 snapping data from that exact BRG1 graph.
- routing_graph_view.py validates/reads the staged BRG1 graph without loading Sweden eagerly.
"""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

from build_routing import build_routing
from gps_snap_index import build_snap_index
from routing_graph_view import RoutingGraphView


DATASET_FORMAT = "BRG1+BRS2+BRH1"
DATASET_FILES = (
    "routing.brg",
    "routing_snap.brs",
    "routing_geometry.brh",
    "routing_stats.json",
)


def build_routing_dataset(source: Path, output: Path) -> dict:
    """Build graph, snap index and geometry together, then publish only after all succeed."""
    source = Path(source)
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)

    staging = output / ".routing_dataset.tmp"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(parents=True)

    try:
        report = build_routing(source, staging)
        graph_path = staging / "routing.brg"
        snap_path = staging / "routing_snap.brs"
        with RoutingGraphView(graph_path) as graph:
            snap_report = build_snap_index(graph, snap_path)

        report = dict(report)
        report["routing_dataset_format"] = DATASET_FORMAT
        report["snap_output_bytes"] = snap_path.stat().st_size
        report["snap_cell_size_m"] = snap_report["cell_size_m"]
        report["snap_cell_count"] = snap_report["cell_count"]
        report["snap_edge_ref_count"] = snap_report["edge_ref_count"]
        (staging / "routing_stats.json").write_text(
            json.dumps(report, indent=2, sort_keys=True),
            encoding="utf-8",
        )

        for name in DATASET_FILES:
            if not (staging / name).is_file():
                raise RuntimeError(f"routing dataset build did not produce {name}")

        for name in DATASET_FILES:
            (staging / name).replace(output / name)
        return report
    finally:
        if staging.exists():
            shutil.rmtree(staging)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Path to Sweden .osm.pbf or a small .osm fixture")
    parser.add_argument("--output", type=Path, default=Path("world_data"))
    args = parser.parse_args()
    build_routing_dataset(args.source, args.output)


if __name__ == "__main__":
    main()
