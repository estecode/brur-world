#!/usr/bin/env python3
"""Extract simple normalized OSM source facts in one libosmium traversal.

This stage deliberately does not create derived OSM/PBF files. It resolves the
provider objects needed by roads/routing/traffic/search/POIs once, then streams
small BRUR source-fact records into independently publishable caches.
"""
from __future__ import annotations

import argparse
import time
from pathlib import Path

import osmium

from area_source_cache import is_poi_tags
from highway_facts import HighwayFactWriter
from normalized_source_facts import FactWriter
from world_common import ensure_pbf, project

SCHEMAS = {"pois": 1, "addresses": 1, "traffic_signals": 1}
FAST_ROUTES = ("highways", "pois", "addresses", "traffic_signals")
ROUTING_TAGS = {
    "highway", "oneway", "junction", "maxspeed", "maxspeed:forward", "maxspeed:backward",
    "access", "vehicle", "motor_vehicle", "motorcar", "service", "lanes", "surface",
    "bridge", "tunnel", "layer", "name",
}
ROAD_TAGS = ROUTING_TAGS | {"width", "lit"}
ADDRESS_TAGS = {
    "addr:housenumber", "addr:street", "addr:place", "addr:postcode", "addr:city", "addr:suburb",
}
PROGRESS_SECONDS = 10.0


def _tags(tags, allowed: set[str] | None = None) -> dict[str, str]:
    if allowed is None:
        return {str(tag.k): str(tag.v) for tag in tags}
    return {str(tag.k): str(tag.v) for tag in tags if str(tag.k) in allowed}


def _has_address(tags) -> bool:
    number = str(tags.get("addr:housenumber") or "").strip()
    street = str(tags.get("addr:street") or tags.get("addr:place") or "").strip()
    return bool(number and street)


def _way_points(way) -> tuple[list[int], list[tuple[float, float]], list[list[float]]]:
    node_ids: list[int] = []
    lonlat: list[tuple[float, float]] = []
    projected: list[list[float]] = []
    for node in way.nodes:
        if not node.location.valid():
            raise osmium.InvalidLocationError("invalid way-node location")
        lon = float(node.lon)
        lat = float(node.lat)
        node_ids.append(int(node.ref))
        lonlat.append((lon, lat))
        x, y = project(lon, lat)
        projected.append([x, y])
    return node_ids, lonlat, projected


class FactHandler(osmium.SimpleHandler):
    def __init__(self, writers: dict[str, object]) -> None:
        super().__init__()
        self.writers = writers
        self.nodes = 0
        self.ways = 0
        self.started = time.monotonic()
        self.last_progress = self.started

    def _writer_records(self, writer: object) -> int:
        return int(getattr(writer, "records", 0))

    def _progress(self) -> None:
        now = time.monotonic()
        if now - self.last_progress < PROGRESS_SECONDS:
            return
        elapsed = max(0.001, now - self.started)
        counts = " ".join(f"{name}={self._writer_records(writer):,}" for name, writer in self.writers.items())
        print(
            f"[fast-facts] nodes={self.nodes:,} ways={self.ways:,} {counts} "
            f"elapsed={elapsed:.1f}s rate={(self.nodes + self.ways) / elapsed:,.0f}/s",
            flush=True,
        )
        self.last_progress = now

    def node(self, node: osmium.osm.Node) -> None:
        self.nodes += 1
        self._progress()
        if "traffic_signals" in self.writers and node.tags.get("highway") == "traffic_signals" and node.location.valid():
            writer = self.writers["traffic_signals"]
            assert isinstance(writer, FactWriter)
            writer.write({"osm_id": int(node.id), "lon": float(node.lon), "lat": float(node.lat), "tags": _tags(node.tags)})
        if "addresses" in self.writers and _has_address(node.tags) and node.location.valid():
            x, y = project(node.lon, node.lat)
            writer = self.writers["addresses"]
            assert isinstance(writer, FactWriter)
            writer.write({"osm_type": "node", "osm_id": int(node.id), "x": x, "y": y, "tags": _tags(node.tags, ADDRESS_TAGS)})
        if "pois" in self.writers:
            tags = _tags(node.tags)
            if is_poi_tags(tags) and node.location.valid():
                x, y = project(node.lon, node.lat)
                writer = self.writers["pois"]
                assert isinstance(writer, FactWriter)
                writer.write({"osm_type": "node", "osm_id": int(node.id), "x": x, "y": y, "tags": tags})

    def way(self, way: osmium.osm.Way) -> None:
        self.ways += 1
        self._progress()
        highway = str(way.tags.get("highway") or "").strip()
        need_highway = "highways" in self.writers and bool(highway)
        need_address = "addresses" in self.writers and _has_address(way.tags)
        poi_tags = _tags(way.tags) if "pois" in self.writers else None
        need_poi = poi_tags is not None and is_poi_tags(poi_tags)
        if not (need_highway or need_address or need_poi):
            return
        try:
            node_ids, lonlat, projected = _way_points(way)
        except osmium.InvalidLocationError:
            return
        if not node_ids:
            return
        if need_highway:
            writer = self.writers["highways"]
            assert isinstance(writer, HighwayFactWriter)
            writer.write_way(int(way.id), node_ids, lonlat, _tags(way.tags, ROAD_TAGS))
        x = sum(point[0] for point in projected) / len(projected)
        y = sum(point[1] for point in projected) / len(projected)
        if need_address:
            writer = self.writers["addresses"]
            assert isinstance(writer, FactWriter)
            writer.write({"osm_type": "way", "osm_id": int(way.id), "x": x, "y": y, "tags": _tags(way.tags, ADDRESS_TAGS)})
        if need_poi:
            writer = self.writers["pois"]
            assert isinstance(writer, FactWriter)
            writer.write({"osm_type": "way", "osm_id": int(way.id), "x": x, "y": y, "geometry": projected, "tags": poi_tags})


def build_fast_facts(source: Path, outputs: dict[str, Path]) -> dict[str, dict]:
    ensure_pbf(source)
    unknown = sorted(set(outputs) - set(FAST_ROUTES))
    if unknown:
        raise ValueError(f"unsupported fast-fact routes: {', '.join(unknown)}")
    writers: dict[str, object] = {}
    for name, path in outputs.items():
        writers[name] = HighwayFactWriter(path) if name == "highways" else FactWriter(path, SCHEMAS[name])
    started = time.monotonic()
    print(f"[fast-facts] START source={source.name} routes={','.join(outputs)}", flush=True)
    try:
        handler = FactHandler(writers)
        handler.apply_file(str(source), locations=True)
        reports = {name: getattr(writer, "publish")() for name, writer in writers.items()}
    except BaseException:
        for writer in writers.values():
            getattr(writer, "abort")()
        raise
    elapsed = time.monotonic() - started
    for name, report in reports.items():
        print(
            f"[fast-facts] DONE route={name} records={report['records']:,} "
            f"bytes={report['size_bytes']:,} sha256={str(report['sha256'])[:12]}...",
            flush=True,
        )
    print(f"[fast-facts] DONE all elapsed={elapsed:.1f}s", flush=True)
    return reports


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--routes", default=",".join(FAST_ROUTES))
    args = parser.parse_args()
    routes = tuple(name.strip() for name in args.routes.split(",") if name.strip())
    outputs = {name: args.output_dir / f"{name}.brfacts" for name in routes}
    build_fast_facts(args.source, outputs)


if __name__ == "__main__":
    main()
