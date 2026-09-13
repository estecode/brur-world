#!/usr/bin/env python3
"""Validate traffic-intersection modeling against existing Sweden runtime data.

Dependencies:
- Reads generated BTS1 traffic_signals.json and authoritative BRG1 routing.brg only.
- Uses traffic_intersections production logic; never reads PBF or creates another road graph.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from routing_graph import load_brg1
from traffic_intersections import build_from_runtime_data


def check(world_data: Path) -> dict:
    signals_path = world_data / "traffic_signals.json"
    graph_path = world_data / "routing.brg"
    if not signals_path.is_file() or not graph_path.is_file():
        raise SystemExit("traffic intersection real-data check requires traffic_signals.json and routing.brg")

    signal_dataset = json.loads(signals_path.read_text(encoding="utf-8"))
    graph = load_brg1(graph_path)
    report = build_from_runtime_data(signal_dataset, graph)
    resolved_signals = sum(len(item.approaches) for item in report.intersections)
    explicit_stops = sum(1 for item in report.intersections for row in item.approaches if row.stop.source == "explicit")
    derived_stops = sum(1 for item in report.intersections for row in item.approaches if row.stop.source == "derived")
    direction_sources: dict[str, int] = {}
    relationship_sources: dict[str, int] = {}
    for item in report.intersections:
        for row in item.approaches:
            direction_sources[row.direction_source] = direction_sources.get(row.direction_source, 0) + 1
            relationship_sources[row.relationship_source] = relationship_sources.get(row.relationship_source, 0) + 1

    dense = sorted(
        report.intersections,
        key=lambda item: (-len(item.movements), -len(item.approaches), item.junction_osm_node_id),
    )[:5]
    if not report.intersections:
        raise SystemExit("traffic intersection real-data check produced no intersections")
    if report.movement_count <= 0 or report.conflict_count <= 0:
        raise SystemExit("traffic intersection real-data check produced no movement/conflict model")
    if not any(len(item.approaches) >= 3 and len(item.exits) >= 3 for item in report.intersections):
        raise SystemExit("traffic intersection real-data check found no complex 3+ approach junction")

    result = {
        "source_signals": len(signal_dataset.get("signals", [])),
        "resolved_signals": resolved_signals,
        "unresolved_signals": len(report.unresolved_signal_ids),
        "intersections": len(report.intersections),
        "movements": report.movement_count,
        "conflicts": report.conflict_count,
        "explicit_stops": explicit_stops,
        "derived_stops": derived_stops,
        "direction_sources": dict(sorted(direction_sources.items())),
        "relationship_sources": dict(sorted(relationship_sources.items())),
        "dense_examples": [
            {
                "id": item.id,
                "approaches": len(item.approaches),
                "movements": len(item.movements),
                "conflicts": len(item.conflicts),
            }
            for item in dense
        ],
    }
    print("TRAFFIC_INTERSECTIONS_REAL_DATA=" + json.dumps(result, sort_keys=True, separators=(",", ":")))
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("world_data", type=Path, nargs="?", default=Path("world_data"))
    args = parser.parse_args()
    check(args.world_data)


if __name__ == "__main__":
    main()
