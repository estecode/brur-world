"""Build BRG1/BRH1 directly from normalized highway source facts."""
from __future__ import annotations

import json
import time
from pathlib import Path

from build_routing import _finish_graph, _validate_written_brg1, _write_geometry, _write_graph
from compressed_routing import BreakpointIndex, CompressedGraphAccumulator
from highway_facts import iter_highway_ways
from route_geometry import validate_route_geometry, validate_route_geometry_alignment


def build_routing_facts(source: Path, output: Path) -> dict:
    started = time.perf_counter()
    topology = BreakpointIndex()
    print(f"[routing] Phase 1a/4 indexing normalized highway facts: {source}", flush=True)
    for way_count, way in enumerate(iter_highway_ways(source), 1):
        topology.observe_way(list(way.node_ids), str(way.tags.get("highway", "")).strip())
        if way_count % 250_000 == 0:
            print(
                f"[routing] Phase 1a/4: {way_count:,} ways, {topology.routable_way_count:,} routable, "
                f"{len(topology.breakpoints):,} breakpoints",
                flush=True,
            )
    topology.release_seen_nodes()

    accumulator = CompressedGraphAccumulator(topology.breakpoints)
    try:
        print("[routing] Phase 1b/4 building compressed routing edges from facts", flush=True)
        for processed, way in enumerate(iter_highway_ways(source), 1):
            accumulator.add_way(way)
            if processed % 250_000 == 0:
                print(
                    f"[routing] Phase 1b/4: {processed:,} ways, {accumulator.pending_node_count:,} nodes, "
                    f"{accumulator.pending_edge_count:,} directed edges",
                    flush=True,
                )

        graph = _finish_graph(accumulator)
        output.mkdir(parents=True, exist_ok=True)
        graph_path = output / "routing.brg"
        geometry_path = output / "routing_geometry.brh"
        temp_graph_path = output / "routing.brg.tmp"
        temp_geometry_path = output / "routing_geometry.brh.tmp"
        stats_path = output / "routing_stats.json"
        for temporary in (temp_graph_path, temp_geometry_path):
            if temporary.exists():
                temporary.unlink()

        try:
            _write_graph(graph, temp_graph_path)
            _write_geometry(accumulator, temp_geometry_path)
            _validate_written_brg1(temp_graph_path, len(graph.nodes), len(graph.edges))
            _, geometry_points = validate_route_geometry(temp_geometry_path, len(graph.edges))
            if geometry_points != accumulator.geometry_point_count:
                raise RuntimeError(
                    f"BRH1 point count mismatch: expected {accumulator.geometry_point_count:,}, got {geometry_points:,}"
                )
            validate_route_geometry_alignment(temp_graph_path, temp_geometry_path)
            temp_graph_path.replace(graph_path)
            temp_geometry_path.replace(geometry_path)
        except BaseException:
            for temporary in (temp_graph_path, temp_geometry_path):
                if temporary.exists():
                    temporary.unlink()
            raise

        elapsed = time.perf_counter() - started
        report = accumulator.stats.to_dict()
        report.update({
            "format": "BRG1+BRH1",
            "topology_compressed": True,
            "normalized_source_facts": True,
            "original_shape_segment_count": accumulator.original_shape_segments,
            "route_geometry_point_count": accumulator.geometry_point_count,
            "node_count": len(graph.nodes),
            "directed_edge_count": len(graph.edges),
            "build_seconds": round(elapsed, 3),
            "output_bytes": graph_path.stat().st_size,
            "geometry_output_bytes": geometry_path.stat().st_size,
        })
        stats_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
        print(
            f"[routing] DONE ways={report['way_count']:,} nodes={len(graph.nodes):,} edges={len(graph.edges):,} "
            f"elapsed={elapsed:.1f}s",
            flush=True,
        )
        return report
    finally:
        accumulator.close()
