#!/usr/bin/env python3
"""Build BSI1 GPS search data from imported POIs plus OSM address facts.

Dependencies:
- Reads world_data/pois.jsonl produced by build_features.py.
- Reads the source PBF offline only to collect address positions; runtime never parses PBF.
- Writes portable BSI1 JSONL consumed by gps_search.py.
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import osmium

from gps_search import SearchRecord, normalize_search_text, write_search_index
from world_common import ensure_pbf, project

PROGRESS_INTERVAL = 5_000_000


def _address_display(tags: osmium.osm.TagList) -> tuple[str, str] | None:
    number = tags.get("addr:housenumber")
    street = tags.get("addr:street") or tags.get("addr:place")
    if not number or not street:
        return None
    locality = tags.get("addr:city") or tags.get("addr:suburb") or tags.get("addr:postcode") or ""
    display = f"{street} {number}".strip()
    return display, locality


class AddressHandler(osmium.SimpleHandler):
    """Collect address nodes/ways without retaining unrelated source objects."""

    def __init__(self) -> None:
        super().__init__()
        self.records: list[SearchRecord] = []
        self.scanned_nodes = 0
        self.scanned_ways = 0
        self.started = time.monotonic()
        self._next_progress = PROGRESS_INTERVAL

    def _progress(self) -> None:
        processed = self.scanned_nodes + self.scanned_ways
        if processed < self._next_progress:
            return
        elapsed = max(0.001, time.monotonic() - self.started)
        print(
            f"[search] scanned {processed:,} OSM objects | addresses {len(self.records):,} | "
            f"{elapsed:.1f}s | {processed / elapsed:,.0f}/s",
            flush=True,
        )
        self._next_progress += PROGRESS_INTERVAL

    def node(self, node: osmium.osm.Node) -> None:
        self.scanned_nodes += 1
        self._progress()
        address = _address_display(node.tags)
        if address is None or not node.location.valid():
            return
        display, subtitle = address
        x, y = project(node.lon, node.lat)
        self.records.append(_record("address", "node", int(node.id), display, subtitle, x, y))

    def way(self, way: osmium.osm.Way) -> None:
        self.scanned_ways += 1
        self._progress()
        address = _address_display(way.tags)
        if address is None:
            return
        points: list[tuple[float, float]] = []
        try:
            for node in way.nodes:
                if node.location.valid():
                    points.append(project(node.lon, node.lat))
        except osmium.InvalidLocationError:
            return
        if not points:
            return
        x = sum(point[0] for point in points) / len(points)
        y = sum(point[1] for point in points) / len(points)
        display, subtitle = address
        self.records.append(_record("address", "way", int(way.id), display, subtitle, x, y))


def _record(kind: str, osm_type: str, osm_id: int, display: str, subtitle: str, x: float, y: float) -> SearchRecord:
    return SearchRecord(
        f"{kind}:{osm_type}:{osm_id}",
        kind,
        display,
        float(x),
        float(y),
        subtitle,
        normalize_search_text(f"{display} {subtitle}"),
    )


def _poi_kind(tags: dict[str, str]) -> str:
    for key in ("amenity", "shop", "tourism", "healthcare", "emergency", "railway", "public_transport"):
        value = tags.get(key)
        if value:
            return value
    return "poi"


def load_named_pois(path: Path) -> list[SearchRecord]:
    records: list[SearchRecord] = []
    if not path.is_file():
        return records
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            item = json.loads(line)
            tags = {str(key): str(value) for key, value in item.get("tags", {}).items()}
            name = tags.get("name") or tags.get("brand") or tags.get("operator")
            if not name:
                continue
            osm_type = str(item.get("osm_type", "unknown"))
            osm_id = int(item["osm_id"])
            kind = _poi_kind(tags)
            subtitle = tags.get("addr:city") or tags.get("addr:street") or kind.replace("_", " ")
            records.append(
                SearchRecord(
                    f"poi:{osm_type}:{osm_id}",
                    "poi",
                    name,
                    float(item["x"]),
                    float(item["y"]),
                    subtitle,
                    normalize_search_text(f"{name} {subtitle} {kind}"),
                )
            )
    return records


def build_search_index(pbf: Path, output: Path) -> Path:
    ensure_pbf(pbf)
    output.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    poi_records = load_named_pois(output / "pois.jsonl")
    print(f"[search] named imported POIs: {len(poi_records):,}", flush=True)
    print(f"[search] reading addresses from {pbf} ...", flush=True)
    handler = AddressHandler()
    handler.apply_file(str(pbf), locations=True)
    records = poi_records + handler.records
    path = output / "search_index.jsonl"
    write_search_index(records, path)
    print(f"[search] addresses: {len(handler.records):,}", flush=True)
    print(f"[search] total searchable records: {len(records):,}", flush=True)
    print(f"[search] output: {path} ({path.stat().st_size:,} bytes)", flush=True)
    print(f"[search] build time: {time.monotonic() - started:.1f}s", flush=True)
    return path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pbf", type=Path)
    parser.add_argument("--output", type=Path, default=Path("world_data"))
    args = parser.parse_args()
    build_search_index(args.pbf, args.output)


if __name__ == "__main__":
    main()
