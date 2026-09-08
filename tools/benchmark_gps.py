#!/usr/bin/env python3
"""Benchmark deterministic gameplay GPS routing on a BRG1 graph.

Dependencies:
- routing_graph_view.py memory-maps BRG1 without expanding Sweden into Python objects.
- gps_snap_index.py memory-maps the offline BRS2 snap index.
- gps_astar.py performs one admissible multi-source/multi-target A* search for snapped routes.
- world_common.py projects stable geographic benchmark points into world coordinates.
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
from world_common import project


# Real geographic pairs avoid the previous array-index sampling problem where a
# nominal "short" case could accidentally be 360 km or land on a non-routable edge.
BENCHMARK_CASES = (
    ("city", (18.0686, 59.3293), (18.0009, 59.3600)),          # Stockholm -> Solna
    ("regional", (18.0686, 59.3293), (17.6389, 59.8586)),      # Stockholm -> Uppsala
    ("long", (18.0686, 59.3293), (11.9746, 57.7089)),          # Stockholm -> Gothenburg
)


def _timed(label: str, fn):
    started = time.perf_counter()
    result = fn()
    elapsed = time.perf_counter() - started
    print(f"[gps-bench] {label}: {elapsed * 1000.0:.2f} ms", flush=True)
    return result, elapsed


def _parse_preferences(value: str) -> tuple[RoutingPreference, ...]:
    if value == "all":
        return tuple(RoutingPreference)
    wanted = []
    for item in value.split(","):
        text = item.strip()
        if not text:
            continue
        try:
            wanted.append(RoutingPreference(text))
        except ValueError as exc:
            choices = ", ".join(preference.value for preference in RoutingPreference)
            raise argparse.ArgumentTypeError(f"unknown preference {text!r}; use all or one of: {choices}") from exc
    if not wanted:
        raise argparse.ArgumentTypeError("at least one routing preference is required")
    return tuple(wanted)


def benchmark(
    path: Path,
    snap_path: Path,
    max_snap_distance_m: float = 250.0,
    preferences: tuple[RoutingPreference, ...] = (RoutingPreference.FASTEST,),
) -> int:
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
                f"cell {snap_index.cell_size_m:.0f} m, max legal {snap_index.max_legal_speed_kmh:.1f} km/h",
                flush=True,
            )
            if snap_index.cell_size_m > 512.0:
                print(
                    "[gps-bench] WARNING: snap index is coarse; rebuild with "
                    "python tools/build_snap_index.py --cell-size 256",
                    flush=True,
                )
            router = AStarGraphRouter(
                graph,
                RoutingProfile.NORMAL,
                snap_index.max_legal_speed_kmh,
            )
            successful = 0
            for name, start_lonlat, target_lonlat in BENCHMARK_CASES:
                sx, sy = project(*start_lonlat)
                tx, ty = project(*target_lonlat)
                (start, start_candidates), _ = _timed(
                    f"{name} start snap",
                    lambda sx=sx, sy=sy: snap_index.snap_with_stats(sx, sy, max_snap_distance_m),
                )
                print(f"[gps-bench]   start candidates: {start_candidates:,}", flush=True)
                (target, target_candidates), _ = _timed(
                    f"{name} target snap",
                    lambda tx=tx, ty=ty: snap_index.snap_with_stats(tx, ty, max_snap_distance_m),
                )
                print(f"[gps-bench]   target candidates: {target_candidates:,}", flush=True)
                if start is None or target is None:
                    print(f"[gps-bench] {name}: snap failed", flush=True)
                    continue
                if not start.directions or not target.directions:
                    raise RuntimeError("BRS2 returned a snapped physical segment without a legal NORMAL direction")
                for preference in preferences:
                    router.last_stats = {}
                    result, elapsed = _timed(
                        f"{name} {preference.value}",
                        lambda preference=preference: router.route_snaps(start, target, EdgeCostPolicy(preference)),
                    )
                    stats = router.last_stats
                    print(
                        f"[gps-bench]   search: {stats.get('searches', 0)} | "
                        f"settled {stats.get('settled', 0):,} | relaxed {stats.get('relaxed', 0):,} | "
                        f"queue peak {stats.get('queue_peak', 0):,}",
                        flush=True,
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
    parser.add_argument("--max-snap-distance", type=float, default=250.0)
    parser.add_argument(
        "--preferences",
        type=_parse_preferences,
        default=(RoutingPreference.FASTEST,),
        help="comma-separated routing preferences or 'all' (default: fastest)",
    )
    args = parser.parse_args()
    if not args.snap_index.is_file():
        raise SystemExit(
            f"Snap index not found: {args.snap_index}. Run: python tools/build_snap_index.py {args.graph}"
        )
    successes = benchmark(args.graph, args.snap_index, args.max_snap_distance, args.preferences)
    print(f"[gps-bench] successful route/preference samples: {successes}", flush=True)


if __name__ == "__main__":
    main()
