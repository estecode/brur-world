#!/usr/bin/env python3
"""Benchmark deterministic GPS routing on a BRG1 graph.

Dependencies:
- routing_graph_view.py memory-maps BRG1 without expanding Sweden into Python objects.
- gps_snap_index.py memory-maps the offline BRS2 snap index.
- gps_astar.py performs large-graph A* route search.
- This is a measurement tool only; it does not affect runtime behavior.
"""

from __future__ import annotations

import argparse
import time
from pathlib import Path

from gps_astar import AStarGraphRouter
from gps_routing import EdgeCostPolicy, RoutingPreference
from gps_snap_index import PersistentRoadSnapIndex
from routing_graph import RoutingProfile
from routing_graph_view import RoutingGraphView


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


def benchmark(path: Path, snap_path: Path, max_snap_distance_m: float = 5000.0) -> int:
    graph, _ = _timed("map BRG1", lambda: RoutingGraphView(path))
    try:
        print(f"[gps-bench] graph: {len(graph.nodes):,} nodes, {len(graph.edges):,} directed edges", flush=True)
        snap_index, _ = _timed(
            "map BRS2 snap index",
            lambda: PersistentRoadSnapIndex(graph, snap_path, RoutingProfile.NORMAL),
        )
        try:
            print(
                f"[gps-bench] snap index: {snap_index.cell_count:,} cells, {snap_index.ref_count:,} refs, "
                f"max legal {snap_index.max_legal_speed_kmh:.1f} km/h",
                flush=True,
            )
            router = AStarGraphRouter(
                graph,
                RoutingProfile.NORMAL,
                snap_index.max_legal_speed_kmh,
            )

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
        finally:
            snap_index.close()
    finally:
        graph.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("graph", type=Path, nargs="?", default=Path("world_data/routing.brg"))
    parser.add_argument("--snap-index", type=Path, default=Path("world_data/routing_snap.brs"))
    parser.add_argument("--max-snap-distance", type=float, default=5000.0)
    args = parser.parse_args()
    if not args.snap_index.is_file():
        raise SystemExit(
            f"Snap index not found: {args.snap_index}. Run: python tools/build_snap_index.py {args.graph}"
        )
    try:
        successes = benchmark(args.graph, args.snap_index, args.max_snap_distance)
    except ValueError as exc:
        if "BRS2" in str(exc) or "snap index magic" in str(exc):
            raise SystemExit(
                f"{exc}\nRebuild the snap index: python tools/build_snap_index.py {args.graph}"
            ) from exc
        raise
    print(f"[gps-bench] successful route/preference samples: {successes}", flush=True)


if __name__ == "__main__":
    main()
