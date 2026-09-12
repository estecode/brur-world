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

from source_identity import compute_source_identity, reusable_output, write_manifest_entry
from traffic_signals import SignalDraft, build_runtime_dataset, load_runtime_dataset, save_runtime_dataset
from world_common import ensure_pbf, project

PROGRESS_INTERVAL = 5_000_000


@dataclass
class SourceSignal:
    osm_id: int
    lon: float
    lat: float
    tags: dict[str, str]
    highway_way_ids: set[int] = field(default_factory=set)


def _is_signal(tags: dict[str, str]) -> bool:
    return tags.get("highway") == "traffic_signals"


def _xml_source(path: Path) -> tuple[list[SourceSignal], dict[int, list[int]]]:
    root = ET.parse(path).getroot()
    signals: list[SourceSignal] = []
    signal_ids: set[int] = set()
    for node in root.findall("node"):
        tags = {tag.attrib["k"]: tag.attrib["v"] for tag in node.findall("tag")}
        if not _is_signal(tags):
            continue
        osm_id = int(node.attrib["id"])
        signals.append(SourceSignal(osm_id, float(node.attrib["lon"]), float(node.attrib["lat"]), tags))
        signal_ids.add(osm_id)

    memberships: dict[int, list[int]] = {signal_id: [] for signal_id in signal_ids}
    for way in root.findall("way"):
        tags = {tag.attrib["k"]: tag.attrib["v"] for tag in way.findall("tag")}
        if not tags.get("highway"):
            continue
        way_id = int(way.attrib["id"])
        for nd in way.findall("nd"):
            node_id = int(nd.attrib["ref"])
            if node_id in memberships:
                memberships[node_id].append(way_id)
    return signals, memberships


def _pbf_signals(path: Path) -> list[SourceSignal]:
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
                print(f"[traffic-signals] nodes: {self.scanned:,} scanned | {len(signals):,} signals | {self.scanned / elapsed:,.0f}/s", flush=True)
            tags = {str(tag.k): str(tag.v) for tag in node.tags}
            if not _is_signal(tags) or not node.location.valid():
                return
            signals.append(SourceSignal(int(node.id), float(node.lon), float(node.lat), tags))

    handler = SignalHandler()
    handler.apply_file(str(path), locations=True)
    elapsed = time.perf_counter() - handler.started
    print(f"[traffic-signals] nodes: done, {handler.scanned:,} scanned, {len(signals):,} signals in {elapsed:.1f}s", flush=True)
    return signals


def _pbf_memberships(path: Path, signal_ids: set[int]) -> dict[int, list[int]]:
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
            if self.scanned % 250_000 == 0:
                elapsed = max(0.001, time.perf_counter() - self.started)
                linked = sum(1 for values in memberships.values() if values)
                print(f"[traffic-signals] ways: {self.scanned:,} scanned | {self.highways:,} highways | {linked:,} linked signals | {self.scanned / elapsed:,.0f}/s", flush=True)

    handler = MembershipHandler()
    handler.apply_file(str(path))
    elapsed = time.perf_counter() - handler.started
    linked = sum(1 for values in memberships.values() if values)
    print(f"[traffic-signals] ways: done, {handler.scanned:,} scanned, {handler.highways:,} highways, {linked:,} linked signals in {elapsed:.1f}s", flush=True)
    return memberships


def _source(path: Path) -> tuple[list[SourceSignal], dict[int, list[int]]]:
    if path.suffix.lower() in {".osm", ".xml"}:
        if not path.is_file():
            raise SystemExit(f"OSM source not found: {path}")
        return _xml_source(path)
    ensure_pbf(path)
    signals = _pbf_signals(path)
    return signals, _pbf_memberships(path, {signal.osm_id for signal in signals})


def _cached_stats(dataset: dict, destination: Path) -> dict:
    stats = dict(dataset["stats"])
    stats["output_bytes"] = destination.stat().st_size
    stats["build_seconds"] = 0.0
    stats["reused"] = True
    return stats


def build_traffic_signals(source: Path, output: Path) -> dict:
    started = time.perf_counter()
    output.mkdir(parents=True, exist_ok=True)
    destination = output / "traffic_signals.json"
    manifest_path = output / "manifest.json"
    source_identity = compute_source_identity(source)

    cached = reusable_output(
        manifest_path,
        "traffic_signals",
        source_identity,
        destination,
        load_runtime_dataset,
    )
    if cached is not None:
        stats = _cached_stats(cached, destination)
        print(
            "[traffic-signals] reuse "
            f"source={stats['source_signal_count']:,} exported={stats['exported_signal_count']:,} "
            f"bytes={stats['output_bytes']:,}",
            flush=True,
        )
        return stats

    signals, memberships = _source(source)

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

    write_manifest_entry(
        manifest_path,
        "traffic_signals",
        {
            "format": dataset["format"],
            "file": destination.name,
            "source": source_identity,
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
