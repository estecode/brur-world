#!/usr/bin/env python3
"""Measure how much BRG1 can shrink by exact degree-2 chain compression.

Dependencies:
- routing_graph_view.py memory-maps BRG1 without expanding Sweden into Python objects.
- routing_graph.py defines NORMAL-profile edge legality.
- This tool only reports topology facts; it does not alter routing data.
"""

from __future__ import annotations

import argparse
import time
from pathlib import Path

from routing_graph import RoutingProfile, is_edge_allowed
from routing_graph_view import RoutingGraphView


PROGRESS_SECONDS = 5.0


def analyze(path: Path) -> dict[str, int | float]:
    started = time.perf_counter()
    with RoutingGraphView(path) as graph:
        node_count = len(graph.nodes)
        edge_count = len(graph.edges)
        degree2 = 0
        junction_or_endpoint = 0
        isolated = 0
        legal_out_zero = 0
        legal_out_one = 0
        legal_out_two = 0
        legal_out_many = 0
        last_print = started

        for node_index in range(node_count):
            node = graph.nodes[node_index]
            degree = node.adjacency_count
            if degree == 0:
                isolated += 1
            if degree == 2:
                degree2 += 1
            else:
                junction_or_endpoint += 1

            legal_out = 0
            start = node.adjacency_offset
            end = start + node.adjacency_count
            for edge_index in range(start, end):
                if is_edge_allowed(graph.edges[edge_index], RoutingProfile.NORMAL):
                    legal_out += 1
            if legal_out == 0:
                legal_out_zero += 1
            elif legal_out == 1:
                legal_out_one += 1
            elif legal_out == 2:
                legal_out_two += 1
            else:
                legal_out_many += 1

            now = time.perf_counter()
            if now - last_print >= PROGRESS_SECONDS:
                print(
                    f"[core-analysis] {node_index + 1:,}/{node_count:,} nodes | "
                    f"degree-2 {degree2:,} | core {junction_or_endpoint:,} | {now - started:.1f}s",
                    flush=True,
                )
                last_print = now

        elapsed = time.perf_counter() - started
        removable_pct = (degree2 / node_count * 100.0) if node_count else 0.0
        core_pct = (junction_or_endpoint / node_count * 100.0) if node_count else 0.0
        compression_ratio = (node_count / junction_or_endpoint) if junction_or_endpoint else 0.0
        report = {
            "node_count": node_count,
            "edge_count": edge_count,
            "degree2_nodes": degree2,
            "core_nodes": junction_or_endpoint,
            "isolated_nodes": isolated,
            "legal_out_zero": legal_out_zero,
            "legal_out_one": legal_out_one,
            "legal_out_two": legal_out_two,
            "legal_out_many": legal_out_many,
            "degree2_percent": removable_pct,
            "core_percent": core_pct,
            "node_compression_ratio": compression_ratio,
            "seconds": elapsed,
        }
        print(f"[core-analysis] graph: {node_count:,} nodes, {edge_count:,} directed edges", flush=True)
        print(
            f"[core-analysis] degree-2 candidates: {degree2:,} ({removable_pct:.1f}%)",
            flush=True,
        )
        print(
            f"[core-analysis] conservative core: {junction_or_endpoint:,} ({core_pct:.1f}%) | "
            f"node ratio {compression_ratio:.2f}x",
            flush=True,
        )
        print(
            f"[core-analysis] legal out-degree: 0={legal_out_zero:,} 1={legal_out_one:,} "
            f"2={legal_out_two:,} 3+={legal_out_many:,}",
            flush=True,
        )
        print(f"[core-analysis] completed in {elapsed:.2f}s", flush=True)
        return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("graph", type=Path, nargs="?", default=Path("world_data/routing.brg"))
    args = parser.parse_args()
    analyze(args.graph)


if __name__ == "__main__":
    main()
