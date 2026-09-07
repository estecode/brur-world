#!/usr/bin/env python3
"""Build the BRG1 routing graph from OSM input.

Dependencies:
- Uses pyosmium for production .osm.pbf input.
- Uses the standard-library XML reader for tiny .osm test fixtures.
- Delegates graph policy, topology and serialization to routing_graph.py.
"""

from __future__ import annotations

import argparse
import json
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Iterable

from routing_graph import EDGE_RECORD, HEADER, MAGIC, NODE_RECORD, GraphAccumulator, WayInput, write_brg1
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
        rate = processed / elapsed if elapsed > 0.0 else 0.0
        suffix = f", {detail}" if detail else ""
        print(
            f"[routing] {self.label}: {processed:,} processed, {elapsed:.1f}s elapsed, {rate:,.0f}/s{suffix}",
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


def _build_pbf(path: Path, accumulator: GraphAccumulator) -> None:
    try:
        import osmium
    except ImportError as exc:
        raise SystemExit("pyosmium is required for .osm.pbf routing builds") from exc

    progress = _Progress("Phase 1/4 reading PBF ways")

    class RoutingHandler(osmium.SimpleHandler):
        def __init__(self) -> None:
            super().__init__()
            self.way_count = 0
            self.highway_way_count = 0

        def way(self, way: osmium.osm.Way) -> None:
            self.way_count += 1
            highway = way.tags.get("highway")
            if highway is None:
                progress.maybe_print(
                    self.way_count,
                    f"{self.highway_way_count:,} highway ways accepted for policy check",
                )
                return

            self.highway_way_count += 1
            try:
                node_ids = [int(node.ref) for node in way.nodes]
                coords = [(float(node.lon), float(node.lat)) for node in way.nodes]
            except osmium.InvalidLocationError:
                accumulator.stats.skipped_way_count += 1
                progress.maybe_print(
                    self.way_count,
                    f"{self.highway_way_count:,} highway ways accepted for policy check",
                )
                return

            tags = {str(tag.k): str(tag.v) for tag in way.tags}
            accumulator.add_way(WayInput(int(way.id), node_ids, coords, tags))
            progress.maybe_print(
                self.way_count,
                f"{self.highway_way_count:,} highway ways accepted for policy check",
            )

    handler = RoutingHandler()
    handler.apply_file(str(path), locations=True)
    progress.done(
        handler.way_count,
        f"{handler.highway_way_count:,} highway ways accepted for policy check",
    )


def _validate_written_brg1(path: Path, node_count: int, edge_count: int) -> None:
    """Validate the on-disk container without loading a multi-GB graph into Python again."""
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


def build_routing(source: Path, output: Path) -> dict:
    if source.suffix.lower() in {".osm", ".xml"}:
        if not source.is_file():
            raise SystemExit(f"OSM source not found: {source}")
    else:
        ensure_pbf(source)

    started = time.perf_counter()
    accumulator = GraphAccumulator()
    source_bytes = source.stat().st_size
    print(f"[routing] Source: {source} ({source_bytes / (1024 ** 3):.2f} GiB)", flush=True)

    if source.suffix.lower() in {".osm", ".xml"}:
        print("[routing] Phase 1/4 reading OSM fixture ...", flush=True)
        progress = _Progress("Phase 1/4 reading OSM ways")
        count = 0
        for count, way in enumerate(_iter_xml_ways(source), start=1):
            accumulator.add_way(way)
            progress.maybe_print(count)
        progress.done(count)
    else:
        _build_pbf(source, accumulator)

    phase_started = time.perf_counter()
    print(
        f"[routing] Phase 2/4 finalizing graph from {accumulator.stats.way_count:,} routable ways ...",
        flush=True,
    )
    graph = accumulator.finish()
    print(
        f"[routing] Phase 2/4 finalizing graph: done in {time.perf_counter() - phase_started:.1f}s "
        f"({len(graph.nodes):,} nodes, {len(graph.edges):,} directed edges)",
        flush=True,
    )

    output.mkdir(parents=True, exist_ok=True)
    graph_path = output / "routing.brg"
    temp_graph_path = output / "routing.brg.tmp"
    stats_path = output / "routing_stats.json"

    # Never clobber an existing valid graph with an interrupted build.
    if temp_graph_path.exists():
        temp_graph_path.unlink()

    expected_bytes = HEADER.size + len(graph.nodes) * NODE_RECORD.size + len(graph.edges) * EDGE_RECORD.size
    phase_started = time.perf_counter()
    print(
        f"[routing] Phase 3/4 writing BRG1 ({expected_bytes / (1024 ** 3):.2f} GiB expected) ...",
        flush=True,
    )
    try:
        write_brg1(graph, temp_graph_path)
        print(
            f"[routing] Phase 3/4 writing BRG1: done in {time.perf_counter() - phase_started:.1f}s",
            flush=True,
        )

        phase_started = time.perf_counter()
        print("[routing] Phase 4/4 validating BRG1 header and file size ...", flush=True)
        _validate_written_brg1(temp_graph_path, len(graph.nodes), len(graph.edges))
        temp_graph_path.replace(graph_path)
        print(
            f"[routing] Phase 4/4 validating BRG1: done in {time.perf_counter() - phase_started:.1f}s",
            flush=True,
        )
    except BaseException:
        if temp_graph_path.exists():
            temp_graph_path.unlink()
        raise

    elapsed = time.perf_counter() - started
    report = accumulator.stats.to_dict()
    report.update(
        {
            "format": "BRG1",
            "node_count": len(graph.nodes),
            "directed_edge_count": len(graph.edges),
            "build_seconds": round(elapsed, 3),
            "output_bytes": graph_path.stat().st_size,
        }
    )
    stats_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")

    print(f"[routing] Nodes: {len(graph.nodes):,}", flush=True)
    print(f"[routing] Directed edges: {len(graph.edges):,}", flush=True)
    print(f"[routing] Explicit speed edges: {report['explicit_speed_edges']:,}", flush=True)
    print(f"[routing] Fallback speed edges: {report['fallback_speed_edges']:,}", flush=True)
    print(f"[routing] Restricted/special edges: {report['restricted_edges']:,}", flush=True)
    print(f"[routing] Against-oneway edges: {report['against_oneway_edges']:,}", flush=True)
    if report["unknown_maxspeed"]:
        print(f"[routing] Unknown maxspeed values: {report['unknown_maxspeed']}", flush=True)
    print(f"[routing] Output: {graph_path} ({report['output_bytes']:,} bytes)", flush=True)
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
        print("\n[routing] Build interrupted by user; existing routing.brg was left untouched.", flush=True)
        raise SystemExit(130)


if __name__ == "__main__":
    main()
