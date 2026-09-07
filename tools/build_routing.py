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

from routing_graph import GraphAccumulator, WayInput, load_brg1, write_brg1
from world_common import ensure_pbf


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

    class RoutingHandler(osmium.SimpleHandler):
        def way(self, way: osmium.osm.Way) -> None:
            highway = way.tags.get("highway")
            if highway is None:
                return
            try:
                node_ids = [int(node.ref) for node in way.nodes]
                coords = [(float(node.lon), float(node.lat)) for node in way.nodes]
            except osmium.InvalidLocationError:
                accumulator.stats.skipped_way_count += 1
                return
            tags = {str(tag.k): str(tag.v) for tag in way.tags}
            accumulator.add_way(WayInput(int(way.id), node_ids, coords, tags))

    handler = RoutingHandler()
    handler.apply_file(str(path), locations=True)


def build_routing(source: Path, output: Path) -> dict:
    if source.suffix.lower() in {".osm", ".xml"}:
        if not source.is_file():
            raise SystemExit(f"OSM source not found: {source}")
    else:
        ensure_pbf(source)

    started = time.perf_counter()
    accumulator = GraphAccumulator()
    print(f"[routing] Reading {source} ...")

    if source.suffix.lower() in {".osm", ".xml"}:
        for way in _iter_xml_ways(source):
            accumulator.add_way(way)
    else:
        _build_pbf(source, accumulator)

    graph = accumulator.finish()
    output.mkdir(parents=True, exist_ok=True)
    graph_path = output / "routing.brg"
    stats_path = output / "routing_stats.json"
    write_brg1(graph, graph_path)

    # Loading the just-written file catches structural serialization mistakes in every build.
    loaded = load_brg1(graph_path)
    if len(loaded.nodes) != len(graph.nodes) or len(loaded.edges) != len(graph.edges):
        raise RuntimeError("Routing graph round-trip validation failed")

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

    print(f"[routing] Nodes: {len(graph.nodes):,}")
    print(f"[routing] Directed edges: {len(graph.edges):,}")
    print(f"[routing] Explicit speed edges: {report['explicit_speed_edges']:,}")
    print(f"[routing] Fallback speed edges: {report['fallback_speed_edges']:,}")
    print(f"[routing] Restricted/special edges: {report['restricted_edges']:,}")
    print(f"[routing] Against-oneway edges: {report['against_oneway_edges']:,}")
    if report["unknown_maxspeed"]:
        print(f"[routing] Unknown maxspeed values: {report['unknown_maxspeed']}")
    print(f"[routing] Output: {graph_path} ({report['output_bytes']:,} bytes)")
    print(f"[routing] Build time: {elapsed:.2f}s")
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Path to Sweden .osm.pbf or a small .osm test fixture")
    parser.add_argument("--output", type=Path, default=Path("world_data"))
    args = parser.parse_args()
    build_routing(args.source, args.output)


if __name__ == "__main__":
    main()
