#!/usr/bin/env python3
"""Build the BRG1 routing graph and BRH1 route geometry from OSM input.

Dependencies:
- Uses pyosmium for production .osm.pbf input.
- Uses the standard-library XML reader for tiny .osm test fixtures.
- Uses compressed_routing.py to split ways only at routing-relevant OSM nodes while preserving shape geometry.
- Delegates shared routing policy/data definitions to routing_graph.py.
"""

from __future__ import annotations

import argparse
import gc
import json
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Iterable

from compressed_routing import (
    BreakpointIndex,
    CompressedGraphAccumulator,
    write_brg1_with_progress,
)
from route_geometry import validate_route_geometry
from routing_graph import EDGE_RECORD, HEADER, MAGIC, NODE_RECORD, ROAD_CLASS, WayInput
from world_common import ensure_pbf


PROGRESS_INTERVAL_SECONDS = 5.0


class _Progress:
    """Print a periodic heartbeat for long offline build phases."""

    def __init__(self, label: str, interval: float = PROGRESS_INTERVAL_SECONDS) -> None:
        self.label = label
        self.interval = interval
        self.started = time.perf_counter()
        self.last_print = self.started

    def maybe_print(self, processed: int, detail: str = "") -> None:
        now = time.perf_counter()
        if now - self.last_print < self.interval:
            return
        elapsed = now - self.started
        rate = processed / elapsed if processed > 0 and elapsed > 0.0 else 0.0
        suffix = f", {detail}" if detail else ""
        rate_text = f", {rate:,.0f}/s" if processed > 0 else ""
        print(
            f"[routing] {self.label}: {processed:,} processed, {elapsed:.1f}s elapsed{rate_text}{suffix}",
            flush=True,
        )
        self.last_print = now

    def done(self, processed: int, detail: str = "") -> None:
        elapsed = time.perf_counter() - self.started
        suffix = f", {detail}" if detail else ""
        print(f"[routing] {self.label}: done, {processed:,} processed in {elapsed:.1f}s{suffix}", flush=True)


def _iter_xml_ways(path: Path) -> Iterable[WayInput]:
    root = ET.parse(path).getroot()
    coordinates: dict[int, tuple[float, float]] = {}
    for node in root.findall("node"):
        coordinates[int(node.attrib["id"])] = (float(node.attrib["lon"]), float(node.attrib["lat"]))

    for way in root.findall("way"):
        node_ids = [int(nd.attrib["ref"]) for nd in way.findall("nd")]
        try:
            coords = [coordinates[node_id] for node_id in node_ids]
        except KeyError:
            continue
        tags = {tag.attrib["k"]: tag.attrib["v"] for tag in way.findall("tag")}
        yield WayInput(int(way.attrib["id"]), node_ids, coords, tags)


def _index_pbf_topology(path: Path) -> BreakpointIndex:
    """Pass 1: identify endpoints/shared nodes without resolving node locations."""
    try:
        import osmium
    except ImportError as exc:
        raise SystemExit("pyosmium is required for .osm.pbf routing builds") from exc

    topology = BreakpointIndex()
    progress = _Progress("Phase 1a/4 indexing routing topology")

    class TopologyHandler(osmium.SimpleHandler):
        def __init__(self) -> None:
            super().__init__()
            self.way_count = 0
            self.highway_way_count = 0

        def way(self, way: osmium.osm.Way) -> None:
            self.way_count += 1
            highway = str(way.tags.get("highway") or "").strip()
            if not highway:
                progress.maybe_print(
                    self.way_count,
                    f"{self.highway_way_count:,} highway ways, {topology.routable_way_count:,} routable",
                )
                return

            self.highway_way_count += 1
            if highway in ROAD_CLASS:
                topology.observe_way([int(node.ref) for node in way.nodes], highway)

            progress.maybe_print(
                self.way_count,
                f"{self.highway_way_count:,} highway ways, {topology.routable_way_count:,} routable, "
                f"{len(topology.breakpoints):,} breakpoints",
            )

    handler = TopologyHandler()
    # No location index in pass 1: only OSM node identities are needed here.
    handler.apply_file(str(path))
    progress.done(
        handler.way_count,
        f"{handler.highway_way_count:,} highway ways, {topology.routable_way_count:,} routable, "
        f"{topology.seen_node_count:,} unique shape nodes, {len(topology.breakpoints):,} routing breakpoints",
    )
    return topology


def _build_pbf_graph(path: Path, topology: BreakpointIndex) -> CompressedGraphAccumulator:
    """Pass 2: resolve geometry and emit compressed edges between breakpoints."""
    try:
        import osmium
    except ImportError as exc:
        raise SystemExit("pyosmium is required for .osm.pbf routing builds") from exc

    accumulator = CompressedGraphAccumulator(topology.breakpoints)
    progress = _Progress("Phase 1b/4 building compressed routing edges")

    class RoutingHandler(osmium.SimpleHandler):
        def __init__(self) -> None:
            super().__init__()
            self.way_count = 0
            self.routable_candidate_count = 0

        def way(self, way: osmium.osm.Way) -> None:
            self.way_count += 1
            highway = str(way.tags.get("highway") or "").strip()
            if highway not in ROAD_CLASS:
                progress.maybe_print(
                    self.way_count,
                    f"{self.routable_candidate_count:,} routable ways, "
                    f"{accumulator.pending_node_count:,} nodes, {accumulator.pending_edge_count:,} directed edges",
                )
                return

            self.routable_candidate_count += 1
            try:
                node_ids = [int(node.ref) for node in way.nodes]
                coords = [(float(node.lon), float(node.lat)) for node in way.nodes]
            except osmium.InvalidLocationError:
                accumulator.stats.skipped_way_count += 1
                progress.maybe_print(
                    self.way_count,
                    f"{self.routable_candidate_count:,} routable ways, "
                    f"{accumulator.pending_node_count:,} nodes, {accumulator.pending_edge_count:,} directed edges",
                )
                return

            # Only routing-relevant tags are retained for this transient WayInput.
            tags = {str(tag.k): str(tag.v) for tag in way.tags}
            accumulator.add_way(WayInput(int(way.id), node_ids, coords, tags))
            progress.maybe_print(
                self.way_count,
                f"{self.routable_candidate_count:,} routable ways, "
                f"{accumulator.pending_node_count:,} nodes, {accumulator.pending_edge_count:,} directed edges",
            )

    handler = RoutingHandler()
    handler.apply_file(str(path), locations=True)
    progress.done(
        handler.way_count,
        f"{accumulator.stats.way_count:,} routable ways, "
        f"{accumulator.original_shape_segments:,} original shape segments -> "
        f"{accumulator.pending_edge_count:,} directed routing edges",
    )
    return accumulator


def _validate_written_brg1(path: Path, node_count: int, edge_count: int) -> None:
    """Validate the on-disk container without loading a large graph into Python again."""
    expected_size = HEADER.size + node_count * NODE_RECORD.size + edge_count * EDGE_RECORD.size
    actual_size = path.stat().st_size
    if actual_size != expected_size:
        raise RuntimeError(f"BRG1 size mismatch: expected {expected_size:,} bytes, got {actual_size:,}")

    with path.open("rb") as handle:
        raw_header = handle.read(HEADER.size)
    if len(raw_header) != HEADER.size:
        raise RuntimeError("BRG1 header is truncated")
    magic, written_nodes, written_edges = HEADER.unpack(raw_header)
    if magic != MAGIC:
        raise RuntimeError(f"Unexpected BRG1 magic: {magic!r}")
    if written_nodes != node_count or written_edges != edge_count:
        raise RuntimeError(
            "BRG1 header count mismatch: "
            f"expected {node_count:,}/{edge_count:,}, got {written_nodes:,}/{written_edges:,}"
        )


def _finish_graph(accumulator: CompressedGraphAccumulator):
    progressers: dict[str, _Progress] = {}

    def report(stage: str, processed: int, detail: str) -> None:
        progress = progressers.get(stage)
        if progress is None:
            progress = _Progress(f"Phase 2/4 {stage}")
            progressers[stage] = progress
        progress.maybe_print(processed, detail)

    return accumulator.finish(report)


def _write_graph(graph, path: Path) -> None:
    progressers: dict[str, _Progress] = {}

    def report(stage: str, processed: int, detail: str) -> None:
        progress = progressers.get(stage)
        if progress is None:
            progress = _Progress(f"Phase 3/4 {stage}")
            progressers[stage] = progress
        progress.maybe_print(processed, detail)

    write_brg1_with_progress(graph, path, report)


def _write_geometry(accumulator: CompressedGraphAccumulator, path: Path) -> None:
    progressers: dict[str, _Progress] = {}

    def report(stage: str, processed: int, detail: str) -> None:
        progress = progressers.get(stage)
        if progress is None:
            progress = _Progress(f"Phase 3/4 {stage}")
            progressers[stage] = progress
        progress.maybe_print(processed, detail)

    accumulator.write_route_geometry(path, report)


def build_routing(source: Path, output: Path) -> dict:
    if source.suffix.lower() in {".osm", ".xml"}:
        if not source.is_file():
            raise SystemExit(f"OSM source not found: {source}")
    else:
        ensure_pbf(source)

    started = time.perf_counter()
    source_bytes = source.stat().st_size
    print(f"[routing] Source: {source} ({source_bytes / (1024 ** 3):.2f} GiB)", flush=True)

    if source.suffix.lower() in {".osm", ".xml"}:
        ways = list(_iter_xml_ways(source))
        topology = BreakpointIndex()
        progress = _Progress("Phase 1a/4 indexing OSM fixture topology")
        for count, way in enumerate(ways, start=1):
            topology.observe_way(list(way.node_ids), str(way.tags.get("highway", "")).strip())
            progress.maybe_print(count, f"{len(topology.breakpoints):,} breakpoints")
        progress.done(len(ways), f"{len(topology.breakpoints):,} routing breakpoints")
        topology.release_seen_nodes()

        accumulator = CompressedGraphAccumulator(topology.breakpoints)
        progress = _Progress("Phase 1b/4 building OSM fixture edges")
        for count, way in enumerate(ways, start=1):
            accumulator.add_way(way)
            progress.maybe_print(count, f"{accumulator.pending_edge_count:,} directed edges")
        progress.done(len(ways), f"{accumulator.pending_edge_count:,} directed routing edges")
    else:
        topology = _index_pbf_topology(source)
        # The uniqueness set can contain tens of millions of shape-node IDs. It is no
        # longer needed after breakpoint discovery, so free it before the location pass.
        topology.release_seen_nodes()
        gc.collect()
        accumulator = _build_pbf_graph(source, topology)

    phase_started = time.perf_counter()
    print(
        f"[routing] Phase 2/4 finalizing compressed graph from {accumulator.stats.way_count:,} routable ways "
        f"({accumulator.pending_node_count:,} nodes, {accumulator.pending_edge_count:,} directed edges) ...",
        flush=True,
    )
    graph = _finish_graph(accumulator)
    print(
        f"[routing] Phase 2/4 finalizing compressed graph: done in {time.perf_counter() - phase_started:.1f}s "
        f"({len(graph.nodes):,} nodes, {len(graph.edges):,} directed edges, "
        f"{accumulator.geometry_point_count:,} route-shape points)",
        flush=True,
    )

    output.mkdir(parents=True, exist_ok=True)
    graph_path = output / "routing.brg"
    geometry_path = output / "routing_geometry.brh"
    temp_graph_path = output / "routing.brg.tmp"
    temp_geometry_path = output / "routing_geometry.brh.tmp"
    stats_path = output / "routing_stats.json"

    for temporary in (temp_graph_path, temp_geometry_path):
        if temporary.exists():
            temporary.unlink()

    expected_bytes = HEADER.size + len(graph.nodes) * NODE_RECORD.size + len(graph.edges) * EDGE_RECORD.size
    phase_started = time.perf_counter()
    print(
        f"[routing] Phase 3/4 writing BRG1 + BRH1 ({expected_bytes / (1024 ** 3):.2f} GiB BRG1 expected) ...",
        flush=True,
    )
    try:
        _write_graph(graph, temp_graph_path)
        _write_geometry(accumulator, temp_geometry_path)
        print(
            f"[routing] Phase 3/4 writing BRG1 + BRH1: done in {time.perf_counter() - phase_started:.1f}s",
            flush=True,
        )

        phase_started = time.perf_counter()
        print("[routing] Phase 4/4 validating routing graph and route geometry ...", flush=True)
        _validate_written_brg1(temp_graph_path, len(graph.nodes), len(graph.edges))
        _, geometry_points = validate_route_geometry(temp_geometry_path, len(graph.edges))
        if geometry_points != accumulator.geometry_point_count:
            raise RuntimeError(
                f"BRH1 point count mismatch: expected {accumulator.geometry_point_count:,}, got {geometry_points:,}"
            )
        temp_graph_path.replace(graph_path)
        temp_geometry_path.replace(geometry_path)
        print(
            f"[routing] Phase 4/4 validation: done in {time.perf_counter() - phase_started:.1f}s",
            flush=True,
        )
    except BaseException:
        for temporary in (temp_graph_path, temp_geometry_path):
            if temporary.exists():
                temporary.unlink()
        raise

    elapsed = time.perf_counter() - started
    report = accumulator.stats.to_dict()
    report.update(
        {
            "format": "BRG1+BRH1",
            "topology_compressed": True,
            "original_shape_segment_count": accumulator.original_shape_segments,
            "route_geometry_point_count": accumulator.geometry_point_count,
            "node_count": len(graph.nodes),
            "directed_edge_count": len(graph.edges),
            "build_seconds": round(elapsed, 3),
            "output_bytes": graph_path.stat().st_size,
            "geometry_output_bytes": geometry_path.stat().st_size,
        }
    )
    stats_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")

    print(f"[routing] Nodes: {len(graph.nodes):,}", flush=True)
    print(f"[routing] Directed edges: {len(graph.edges):,}", flush=True)
    print(f"[routing] Original shape segments: {accumulator.original_shape_segments:,}", flush=True)
    print(f"[routing] Route-shape points: {accumulator.geometry_point_count:,}", flush=True)
    print(f"[routing] Explicit speed edges: {report['explicit_speed_edges']:,}", flush=True)
    print(f"[routing] Fallback speed edges: {report['fallback_speed_edges']:,}", flush=True)
    print(f"[routing] Restricted/special edges: {report['restricted_edges']:,}", flush=True)
    print(f"[routing] Against-oneway edges: {report['against_oneway_edges']:,}", flush=True)
    if report["unknown_maxspeed"]:
        print(f"[routing] Unknown maxspeed values: {report['unknown_maxspeed']}", flush=True)
    print(f"[routing] Graph: {graph_path} ({report['output_bytes']:,} bytes)", flush=True)
    print(f"[routing] Geometry: {geometry_path} ({report['geometry_output_bytes']:,} bytes)", flush=True)
    print(f"[routing] Build time: {elapsed:.2f}s", flush=True)
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Path to Sweden .osm.pbf or a small .osm test fixture")
    parser.add_argument("--output", type=Path, default=Path("world_data"))
    args = parser.parse_args()
    try:
        build_routing(args.source, args.output)
    except KeyboardInterrupt:
        print("\n[routing] Build interrupted by user; existing routing data was left untouched.", flush=True)
        raise SystemExit(130)


if __name__ == "__main__":
    main()
