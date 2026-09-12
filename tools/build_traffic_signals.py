#!/usr/bin/env python3
"""Compile OSM traffic-signal nodes into normalized runtime intersection data.

Dependencies:
- Reads OSM through pyosmium for production PBF input.
- Uses the standard-library XML reader for tiny deterministic test fixtures.
- Uses shared source identity and world projection helpers; does not create a runtime road graph.
"""

from __future__ import annotations

import argparse
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path

from source_identity import (
    compute_source_identity,
    load_manifest,
    reusable_output,
    source_identity_matches,
    write_manifest_entry,
)
from traffic_signals import SignalDraft, build_runtime_dataset, load_runtime_dataset, save_runtime_dataset
from world_common import ensure_pbf, project

PROGRESS_INTERVAL = 5_000_000
WAY_PROGRESS_INTERVAL = 250_000


@dataclass
class SourceSignal:
    osm_id: int
    lon: float
    lat: float
    tags: dict[str, str]
    highway_way_ids: set[int] = field(default_factory=set)


def _is_signal(tags: dict[str, str]) -> bool:
    return tags.get("highway") == "traffic_signals"


def _progress_count(current: int, total: int | None) -> str:
    if isinstance(total, int) and total >= current and total > 0:
        return f"{current:,} / {total:,}"
    return f"{current:,}"


def _matching_scan_totals(manifest_path: Path, source_identity: dict[str, object]) -> dict[str, int]:
    manifest = load_manifest(manifest_path)
    entry = manifest.get("traffic_signals")
    if not source_identity_matches(entry, source_identity) or not isinstance(entry, dict):
        return {}
    source_scan = entry.get("source_scan")
    if not isinstance(source_scan, dict):
        return {}
    totals: dict[str, int] = {}
    for key in ("nodes", "ways"):
        value = source_scan.get(key)
        if isinstance(value, int) and value >= 0:
            totals[key] = value
    return totals


def _xml_source(path: Path) -> tuple[list[SourceSignal], dict[int, list[int]], dict[str, int]]:
    root = ET.parse(path).getroot()
    nodes = root.findall("node")
    ways = root.findall("way")
    signals: list[SourceSignal] = []
    signal_ids: set[int] = set()
    for node in nodes:
        tags = {tag.attrib["k"]: tag.attrib["v"] for tag in node.findall("tag")}
        if not _is_signal(tags):
            continue
        osm_id = int(node.attrib["id"])
        signals.append(SourceSignal(osm_id, float(node.attrib["lon"]), float(node.attrib["lat"]), tags))
        signal_ids.add(osm_id)

    memberships: dict[int, list[int]] = {signal_id: [] for signal_id in signal_ids}
    for way in ways:
        tags = {tag.attrib["k"]: tag.attrib["v"] for tag in way.findall("tag")}
        if not tags.get("highway"):
            continue
        way_id = int(way.attrib["id"])
        for nd in way.findall("nd"):
            node_id = int(nd.attrib["ref"])
            if node_id in memberships:
                memberships[node_id].append(way_id)
    return signals, memberships, {"nodes": len(nodes), "ways": len(ways)}


def _pbf_signals(path: Path, total_nodes: int | None = None) -> tuple[list[SourceSignal], int]:
    try:
        import osmium
    except ImportError as exc:
        raise SystemExit("pyosmium is required for .osm.pbf traffic-signal builds") from exc

    signals: list[SourceSignal] = []

    class SignalHandler(osmium.SimpleHandler):
        def __init__(self) -> None:
            super().__init__()
            self.scanned = 0
            self.started = time.perf_counter()

        def node(self, node: osmium.osm.Node) -> None:
            self.scanned += 1
            if self.scanned % PROGRESS_INTERVAL == 0:
                elapsed = max(0.001, time.perf_counter() - self.started)
                count = _progress_count(self.scanned, total_nodes)
                print(
                    f"[traffic-signals] nodes: {count} scanned | {len(signals):,} signals | "
                    f"{self.scanned / elapsed:,.0f}/s",
                    flush=True,
                )
            tags = {str(tag.k): str(tag.v) for tag in node.tags}
            if not _is_signal(tags) or not node.location.valid():
                return
            signals.append(SourceSignal(int(node.id), float(node.lon), float(node.lat), tags))

    handler = SignalHandler()
    handler.apply_file(str(path), locations=True)
    elapsed = time.perf_counter() - handler.started
    count = _progress_count(handler.scanned, total_nodes)
    print(
        f"[traffic-signals] nodes: done, {count} scanned, {len(signals):,} signals in {elapsed:.1f}s",
        flush=True,
    )
    return signals, handler.scanned


def _pbf_memberships(
    path: Path,
    signal_ids: set[int],
    total_ways: int | None = None,
) -> tuple[dict[int, list[int]], int]:
    try:
        import osmium
    except ImportError as exc:
        raise SystemExit("pyosmium is required for .osm.pbf traffic-signal builds") from exc

    memberships: dict[int, list[int]] = {signal_id: [] for signal_id in signal_ids}

    class MembershipHandler(osmium.SimpleHandler):
        def __init__(self) -> None:
            super().__init__()
            self.scanned = 0
            self.highways = 0
            self.started = time.perf_counter()

        def way(self, way: osmium.osm.Way) -> None:
            self.scanned += 1
            highway = str(way.tags.get("highway") or "").strip()
            if not highway:
                return
            self.highways += 1
            way_id = int(way.id)
            for ref in way.nodes:
                node_id = int(ref.ref)
                if node_id in memberships:
                    memberships[node_id].append(way_id)
            if self.scanned % WAY_PROGRESS_INTERVAL == 0:
                elapsed = max(0.001, time.perf_counter() - self.started)
                linked = sum(1 for values in memberships.values() if values)
                count = _progress_count(self.scanned, total_ways)
                print(
                    f"[traffic-signals] ways: {count} scanned | {self.highways:,} highways | "
                    f"{linked:,} linked signals | {self.scanned / elapsed:,.0f}/s",
                    flush=True,
                )

    handler = MembershipHandler()
    handler.apply_file(str(path))
    elapsed = time.perf_counter() - handler.started
    linked = sum(1 for values in memberships.values() if values)
    count = _progress_count(handler.scanned, total_ways)
    print(
        f"[traffic-signals] ways: done, {count} scanned, {handler.highways:,} highways, "
        f"{linked:,} linked signals in {elapsed:.1f}s",
        flush=True,
    )
    return memberships, handler.scanned


def _source(
    path: Path,
    known_scan_totals: dict[str, int] | None = None,
) -> tuple[list[SourceSignal], dict[int, list[int]], dict[str, int]]:
    if path.suffix.lower() in {".osm", ".xml"}:
        if not path.is_file():
            raise SystemExit(f"OSM source not found: {path}")
        return _xml_source(path)
    ensure_pbf(path)
    totals = known_scan_totals or {}
    signals, node_count = _pbf_signals(path, totals.get("nodes"))
    memberships, way_count = _pbf_memberships(
        path,
        {signal.osm_id for signal in signals},
        totals.get("ways"),
    )
    return signals, memberships, {"nodes": node_count, "ways": way_count}


def _cached_stats(dataset: dict, destination: Path, scan_totals: dict[str, int]) -> dict:
    stats = dict(dataset["stats"])
    stats["output_bytes"] = destination.stat().st_size
    stats["build_seconds"] = 0.0
    stats["reused"] = True
    stats["source_node_count"] = scan_totals.get("nodes")
    stats["source_way_count"] = scan_totals.get("ways")
    return stats


def build_traffic_signals(source: Path, output: Path) -> dict:
    started = time.perf_counter()
    output.mkdir(parents=True, exist_ok=True)
    destination = output / "traffic_signals.json"
    manifest_path = output / "manifest.json"
    source_identity = compute_source_identity(source)
    known_scan_totals = _matching_scan_totals(manifest_path, source_identity)

    cached = reusable_output(
        manifest_path,
        "traffic_signals",
        source_identity,
        destination,
        load_runtime_dataset,
    )
    if cached is not None:
        stats = _cached_stats(cached, destination, known_scan_totals)
        known = ""
        if known_scan_totals:
            known = (
                f" nodes={known_scan_totals.get('nodes', 0):,}"
                f" ways={known_scan_totals.get('ways', 0):,}"
            )
        print(
            "[traffic-signals] reuse "
            f"source={stats['source_signal_count']:,} exported={stats['exported_signal_count']:,}"
            f"{known} bytes={stats['output_bytes']:,}",
            flush=True,
        )
        return stats

    signals, memberships, scan_totals = _source(source, known_scan_totals)

    drafts: list[SignalDraft] = []
    for signal in signals:
        x, y = project(signal.lon, signal.lat)
        drafts.append(SignalDraft(signal.osm_id, x, y, signal.tags, tuple(sorted(set(memberships.get(signal.osm_id, []))))))

    dataset = build_runtime_dataset(drafts)
    save_runtime_dataset(destination, dataset)

    stats = dict(dataset["stats"])
    elapsed = time.perf_counter() - started
    stats["output_bytes"] = destination.stat().st_size
    stats["build_seconds"] = round(elapsed, 3)
    stats["reused"] = False
    stats["source_node_count"] = scan_totals.get("nodes")
    stats["source_way_count"] = scan_totals.get("ways")

    write_manifest_entry(
        manifest_path,
        "traffic_signals",
        {
            "format": dataset["format"],
            "file": destination.name,
            "source": source_identity,
            "source_scan": scan_totals,
            "source_signal_count": stats["source_signal_count"],
            "exported_signal_count": stats["exported_signal_count"],
        },
    )

    print(
        "[traffic-signals] "
        f"source={stats['source_signal_count']:,} exported={stats['exported_signal_count']:,} "
        f"direction explicit={stats['explicit_direction_count']:,} legacy={stats['legacy_direction_count']:,} "
        f"inferred={stats['inferred_direction_count']:,} unknown={stats['unknown_direction_count']:,} "
        f"stop-lines={stats['explicit_stop_line_count']:,} grouped={stats['grouped_candidate_count']:,} "
        f"ungrouped={stats['ungrouped_candidate_count']:,} bytes={stats['output_bytes']:,} time={elapsed:.2f}s",
        flush=True,
    )
    return stats


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Path to .osm.pbf or tiny .osm fixture")
    parser.add_argument("--output", type=Path, default=Path("world_data"))
    args = parser.parse_args()
    build_traffic_signals(args.source, args.output)


if __name__ == "__main__":
    main()
