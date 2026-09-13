#!/usr/bin/env python3
"""Build and publish the version-bound routing runtime dataset.

Dependencies:
- build_routing.py produces BRG1 graph and BRH1 route geometry from the shared highway source route.
- osm_route_source.py redirects authoritative Sweden PBF input through the reusable OSM source cache.
- gps_snap_index.py produces BRS2 snapping data from that exact BRG1 graph.
- routing_graph_view.py validates/reads the staged BRG1 graph without loading Sweden eagerly.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path

from build_routing import build_routing
from gps_snap_index import build_snap_index
from osm_route_source import resolve_route_source
from routing_graph_view import RoutingGraphView


DATASET_FORMAT = "BRG1+BRS2+BRH1"
DATASET_PAYLOAD_FILES = (
    "routing.brg",
    "routing_snap.brs",
    "routing_geometry.brh",
)
DATASET_FILES = (*DATASET_PAYLOAD_FILES, "routing_stats.json")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_routing_dataset(source: Path, output: Path) -> dict:
    """Build graph, snap index and geometry together, then publish only after all succeed."""
    source = Path(source)
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    source = resolve_route_source(source, output, "highways")

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

        for name in DATASET_PAYLOAD_FILES:
            if not (staging / name).is_file():
                raise RuntimeError(f"routing dataset build did not produce {name}")

        report = dict(report)
        report["routing_dataset_format"] = DATASET_FORMAT
        report["routing_dataset_sha256"] = {
            name: _sha256(staging / name)
            for name in DATASET_PAYLOAD_FILES
        }
        report["snap_output_bytes"] = snap_report["output_bytes"]
        report["snap_cell_count"] = snap_report["cell_count"]
        report["snap_reference_count"] = snap_report["reference_count"]
        report["snap_physical_edge_count"] = snap_report["physical_edge_count"]
        report["snap_max_legal_speed_kmh"] = snap_report["max_legal_speed_kmh"]
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
    parser.add_argument("source", type=Path, help="Path to Sweden .osm.pbf, cached highway .osm, or a small .osm fixture")
    parser.add_argument("--output", type=Path, default=Path("world_data"))
    args = parser.parse_args()
    build_routing_dataset(args.source, args.output)


if __name__ == "__main__":
    main()
