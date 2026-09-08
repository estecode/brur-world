#!/usr/bin/env python3
"""Benchmark deterministic GPS routing on a BRG1 graph.

Dependencies:
- routing_graph.py loads BRG1 fixture or Sweden data.
- gps_routing.py performs snap indexing and route search.
- This is a measurement tool only; it does not affect runtime behavior.
"""

from __future__ import annotations

import argparse
import time
from pathlib import Path

from gps_routing import EdgeCostPolicy, GraphRouter, RoadSnapIndex, RoutingPreference
from routing_graph import RoutingProfile, load_brg1


def _timed(label: str, fn):
    started = time.perf_counter()
    result = fn()
    elapsed = time.perf_counter() - started
    print(f"[gps-bench] {label}: {elapsed * 1000.0:.2f} ms", flush=True)
    return result, elapsed


def _node_world(graph, index: int) -> tuple[float, float]:
    node = graph.nodes[index]
    return node.x, node.y


def _sample_pairs(node_count: int) -> tuple[tuple[str, int, int], ...]:
    if node_count < 2:
        return ()
    anchors = [0, node_count // 8, node_count // 3, node_count // 2, (node_count * 3) // 4, node_count - 1]
    anchors = [max(0, min(node_count - 1, value)) for value in anchors]
    return (
        ("short", anchors[1], anchors[2]),
        ("medium", anchors[1], anchors[4]),
        ("long", anchors[0], anchors[-1]),
    )


def benchmark(path: Path, max_snap_distance_m: float = 5000.0) -> int:
    graph, _ = _timed("load BRG1", lambda: load_brg1(path))
    print(f"[gps-bench] graph: {len(graph.nodes):,} nodes, {len(graph.edges):,} directed edges", flush=True)
    snap_index, _ = _timed("build snap index", lambda: RoadSnapIndex(graph, RoutingProfile.NORMAL))
    router = GraphRouter(graph, RoutingProfile.NORMAL)

    successful = 0
    for name, start_node, target_node in _sample_pairs(len(graph.nodes)):
        sx, sy = _node_world(graph, start_node)
        tx, ty = _node_world(graph, target_node)
        start, _ = _timed(f"{name} start snap", lambda sx=sx, sy=sy: snap_index.snap(sx, sy, max_snap_distance_m))
        target, _ = _timed(f"{name} target snap", lambda tx=tx, ty=ty: snap_index.snap(tx, ty, max_snap_distance_m))
        if start is None or target is None:
            print(f"[gps-bench] {name}: snap failed", flush=True)
            continue
        for preference in RoutingPreference:
            result, elapsed = _timed(
                f"{name} {preference.value}",
                lambda preference=preference: router.route_snaps(start, target, EdgeCostPolicy(preference)),
            )
            if result.success:
                successful += 1
                print(
                    f"[gps-bench]   {result.distance_m / 1000.0:.1f} km | "
                    f"{result.travel_time_s / 60.0:.1f} min | {len(result.steps):,} steps | "
                    f"{elapsed * 1000.0:.2f} ms",
                    flush=True,
                )
            else:
                print(f"[gps-bench]   failed: {result.failure_reason}", flush=True)
    return successful


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("graph", type=Path, nargs="?", default=Path("world_data/routing.brg"))
    parser.add_argument("--max-snap-distance", type=float, default=5000.0)
    args = parser.parse_args()
    successes = benchmark(args.graph, args.max_snap_distance)
    print(f"[gps-bench] successful route/preference samples: {successes}", flush=True)


if __name__ == "__main__":
    main()
