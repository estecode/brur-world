#!/usr/bin/env python3
"""Build BSI1 GPS search data from imported POIs plus OSM address facts.

Dependencies:
- Reads world_data/pois.jsonl produced by build_features.py.
- Reads the source PBF offline only to collect address positions; runtime never parses PBF.
- Writes portable BSI1 JSONL consumed by gps_search.py and the BSI2 binary compiler.
"""

from __future__ import annotations

import argparse
import json
import math
import time
from dataclasses import dataclass
from pathlib import Path

import osmium

from gps_search import SearchRecord, normalize_search_text, write_search_index
from world_common import ensure_pbf, project

PROGRESS_INTERVAL = 5_000_000
POSTCODE_GRID_METERS = 250.0
POSTCODE_NEARBY_RADIUS_METERS = 500.0
POSTCODE_NEARBY_SUPPORT = 2
POSTCODE_NEARBY_SAMPLE_LIMIT = 5


def _join_unique(*values: str | None) -> str:
    parts: list[str] = []
    for value in values:
        text = str(value or "").strip()
        if text and text not in parts:
            parts.append(text)
    return " ".join(parts)


def _clean(value: str | None) -> str:
    return str(value or "").strip()


def _address_parts(tags: osmium.osm.TagList) -> tuple[str, str, str, str] | None:
    number = _clean(tags.get("addr:housenumber"))
    street = _clean(tags.get("addr:street") or tags.get("addr:place"))
    if not number or not street:
        return None
    postcode = _clean(tags.get("addr:postcode"))
    locality = _clean(tags.get("addr:city") or tags.get("addr:suburb") or tags.get("addr:place"))
    display = f"{street} {number}".strip()
    return display, street, postcode, locality


def _postcode_key(street: str, locality: str) -> tuple[str, str] | None:
    street_key = normalize_search_text(street)
    locality_key = normalize_search_text(locality)
    if not street_key or not locality_key:
        return None
    return street_key, locality_key


def _locality_key(locality: str) -> str:
    return normalize_search_text(locality)


def _grid_cell(x: float, y: float) -> tuple[int, int]:
    return math.floor(x / POSTCODE_GRID_METERS), math.floor(y / POSTCODE_GRID_METERS)


@dataclass(frozen=True)
class AddressFact:
    osm_type: str
    osm_id: int
    display: str
    street: str
    postcode: str
    locality: str
    x: float
    y: float


@dataclass(frozen=True)
class PostcodeSample:
    postcode: str
    locality_key: str
    x: float
    y: float


def infer_postcode(
    street: str,
    locality: str,
    known_postcodes: dict[tuple[str, str], set[str]],
) -> str:
    """Infer only unambiguous postcodes already observed on the same street/locality."""
    key = _postcode_key(street, locality)
    if key is None:
        return ""
    values = known_postcodes.get(key, set())
    if len(values) != 1:
        return ""
    return next(iter(values))


def infer_nearby_postcode(
    x: float,
    y: float,
    locality: str,
    sample_grid: dict[tuple[int, int], list[PostcodeSample]],
) -> str:
    """Infer a postcode only when nearby same-locality address samples strongly agree."""
    locality_normalized = _locality_key(locality)
    if not locality_normalized:
        return ""

    cell_x, cell_y = _grid_cell(x, y)
    cell_radius = math.ceil(POSTCODE_NEARBY_RADIUS_METERS / POSTCODE_GRID_METERS)
    radius_sq = POSTCODE_NEARBY_RADIUS_METERS * POSTCODE_NEARBY_RADIUS_METERS
    candidates: list[tuple[float, str]] = []
    for dy in range(-cell_radius, cell_radius + 1):
        for dx in range(-cell_radius, cell_radius + 1):
            for sample in sample_grid.get((cell_x + dx, cell_y + dy), ()):  # type: ignore[arg-type]
                if sample.locality_key != locality_normalized:
                    continue
                distance_sq = (sample.x - x) ** 2 + (sample.y - y) ** 2
                if distance_sq <= radius_sq:
                    candidates.append((distance_sq, sample.postcode))

    candidates.sort(key=lambda item: (item[0], item[1]))
    nearest = candidates[:POSTCODE_NEARBY_SAMPLE_LIMIT]
    if len(nearest) < POSTCODE_NEARBY_SUPPORT:
        return ""
    postcode = nearest[0][1]
    if any(candidate_postcode != postcode for _, candidate_postcode in nearest):
        return ""
    return postcode


class AddressHandler(osmium.SimpleHandler):
    """Collect address facts, then deterministically enrich safe missing postcodes."""

    def __init__(self) -> None:
        super().__init__()
        self.facts: list[AddressFact] = []
        self.known_postcodes: dict[tuple[str, str], set[str]] = {}
        self.postcode_samples: dict[tuple[int, int], list[PostcodeSample]] = {}
        self.inferred_postcodes = 0
        self.inferred_postcodes_nearby = 0
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
            f"[search] scanned {processed:,} OSM objects | addresses {len(self.facts):,} | "
            f"{elapsed:.1f}s | {processed / elapsed:,.0f}/s",
            flush=True,
        )
        self._next_progress += PROGRESS_INTERVAL

    def _append_fact(
        self,
        osm_type: str,
        osm_id: int,
        parts: tuple[str, str, str, str],
        x: float,
        y: float,
    ) -> None:
        display, street, postcode, locality = parts
        self.facts.append(AddressFact(osm_type, osm_id, display, street, postcode, locality, x, y))
        if postcode:
            key = _postcode_key(street, locality)
            if key is not None:
                self.known_postcodes.setdefault(key, set()).add(postcode)
            locality_normalized = _locality_key(locality)
            if locality_normalized:
                sample = PostcodeSample(postcode, locality_normalized, x, y)
                self.postcode_samples.setdefault(_grid_cell(x, y), []).append(sample)

    def node(self, node: osmium.osm.Node) -> None:
        self.scanned_nodes += 1
        self._progress()
        parts = _address_parts(node.tags)
        if parts is None or not node.location.valid():
            return
        x, y = project(node.lon, node.lat)
        self._append_fact("node", int(node.id), parts, x, y)

    def way(self, way: osmium.osm.Way) -> None:
        self.scanned_ways += 1
        self._progress()
        parts = _address_parts(way.tags)
        if parts is None:
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
        self._append_fact("way", int(way.id), parts, x, y)

    def build_records(self) -> list[SearchRecord]:
        records: list[SearchRecord] = []
        inferred = 0
        nearby_inferred = 0
        for fact in self.facts:
            postcode = fact.postcode
            if not postcode:
                postcode = infer_postcode(fact.street, fact.locality, self.known_postcodes)
                if postcode:
                    inferred += 1
                else:
                    postcode = infer_nearby_postcode(
                        fact.x,
                        fact.y,
                        fact.locality,
                        self.postcode_samples,
                    )
                    if postcode:
                        nearby_inferred += 1
            subtitle = _join_unique(postcode, fact.locality)
            records.append(
                _record("address", fact.osm_type, fact.osm_id, fact.display, subtitle, fact.x, fact.y)
            )
        self.inferred_postcodes = inferred + nearby_inferred
        self.inferred_postcodes_nearby = nearby_inferred
        return records


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
            postcode = tags.get("addr:postcode")
            locality = tags.get("addr:city") or tags.get("addr:suburb")
            street = tags.get("addr:street")
            subtitle = _join_unique(postcode, locality, street)
            if not subtitle:
                subtitle = kind.replace("_", " ")
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
    address_records = handler.build_records()
    records = poi_records + address_records
    path = output / "search_index.jsonl"
    write_search_index(records, path)
    print(f"[search] addresses: {len(address_records):,}", flush=True)
    print(f"[search] inferred missing postcodes: {handler.inferred_postcodes:,}", flush=True)
    print(f"[search] inferred from nearby locality samples: {handler.inferred_postcodes_nearby:,}", flush=True)
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
