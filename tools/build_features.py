#!/usr/bin/env python3
"""Export POI/building data from route caches and shared assembled area facts.

Dependencies:
- Reads OSM route caches through pyosmium for node/way POIs.
- Reads BAF1 assembled area facts for buildings/relation POIs when available.
- Uses poi_filter for deterministic offline runtime relevance/category decisions.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import subprocess
import time
from collections import Counter, OrderedDict
from pathlib import Path
from typing import TextIO

import osmium

from area_source_cache import area_source_cache_valid, is_poi_tags, iter_area_facts
from poi_filter import excluded_poi_category, runtime_poi_category
from world_common import TILE_SIZE, ensure_pbf, project

EXPORTER_VERSION = "poi-v6-shared-area-cache"
POI_PROGRESS_INTERVAL = 5_000_000

POI_KEYS = {
    "amenity", "shop", "tourism", "leisure", "office", "healthcare", "emergency",
    "public_transport", "railway", "aeroway", "craft", "historic", "sport", "club",
    "man_made", "information", "advertising",
}
SPECIAL_HIGHWAY_POIS = {"speed_camera", "services", "rest_area", "bus_stop", "elevator"}


class TileJsonlWriter:
    """Filter and write runtime POI tiles with a small LRU of open files."""

    def __init__(self, directory: Path, max_open: int = 32, staged: bool = True) -> None:
        self.directory = directory
        self.max_open = max_open
        self.files: OrderedDict[tuple[int, int], TextIO] = OrderedDict()
        self.records = 0
        self.included: Counter[str] = Counter()
        self.excluded: Counter[str] = Counter()
        self.published = not staged
        self.staged = staged
        if staged:
            stamp = f"{os.getpid()}-{time.time_ns()}"
            self.write_directory = directory.parent / f".{directory.name}.build-{stamp}"
            self.write_directory.mkdir(parents=True, exist_ok=False)
        else:
            self.write_directory = directory
            self.write_directory.mkdir(parents=True, exist_ok=True)

    def write(self, record: dict) -> None:
        category = runtime_poi_category(record["tags"])
        if category is None:
            self.excluded[excluded_poi_category(record["tags"])] += 1
            return
        runtime_record = runtime_poi_record(record, category)
        key = (math.floor(float(runtime_record["x"]) / TILE_SIZE), math.floor(float(runtime_record["y"]) / TILE_SIZE))
        file = self.files.pop(key, None)
        if file is None:
            file = (self.write_directory / f"{key[0]}_{key[1]}.jsonl").open("a", encoding="utf-8")
        self.files[key] = file
        write_jsonl(file, runtime_record)
        self.records += 1
        self.included[category] += 1
        if len(self.files) > self.max_open:
            _, oldest = self.files.popitem(last=False)
            oldest.close()

    def close(self) -> None:
        for file in self.files.values():
            file.close()
        self.files.clear()

    def publish(self) -> None:
        if not self.staged:
            self.close()
            return
        self.close()
        stale: Path | None = None
        if self.directory.exists():
            stale = self.directory.parent / f".{self.directory.name}.old-{os.getpid()}-{time.time_ns()}"
            self.directory.rename(stale)
        try:
            self.write_directory.rename(self.directory)
            self.published = True
        except Exception:
            if stale is not None and stale.exists() and not self.directory.exists():
                stale.rename(self.directory)
            raise
        if stale is not None and stale.exists():
            shutil.rmtree(stale, ignore_errors=True)

    def cleanup(self) -> None:
        self.close()
        if self.staged and not self.published and self.write_directory.exists():
            shutil.rmtree(self.write_directory, ignore_errors=True)


def git_revision() -> str:
    try:
        return subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], stderr=subprocess.DEVNULL, text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def print_version() -> None:
    print(f"build_features {EXPORTER_VERSION} | git {git_revision()}", flush=True)


def tags_dict(tags: osmium.osm.TagList) -> dict[str, str]:
    return {tag.k: tag.v for tag in tags}


def is_poi(tags: osmium.osm.TagList) -> bool:
    return is_poi_tags(tags_dict(tags))


def write_jsonl(file: TextIO, record: dict) -> None:
    file.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")


def runtime_poi_record(record: dict, category: str) -> dict:
    return {
        "osm_type": record["osm_type"], "osm_id": record["osm_id"],
        "x": record["x"], "y": record["y"], "category": category, "tags": record["tags"],
    }


def point_average(points: list[list[float]]) -> tuple[float, float]:
    return (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))


def projected_way(nodes: osmium.osm.WayNodeList) -> list[list[float]]:
    points: list[list[float]] = []
    for node in nodes:
        if node.location.valid():
            x, y = project(node.lon, node.lat)
            points.append([x, y])
    return points


def projected_ring(ring: osmium.osm.NodeRefList) -> list[list[float]]:
    points: list[list[float]] = []
    for node in ring:
        if node.location.valid():
            x, y = project(node.lon, node.lat)
            points.append([x, y])
    if len(points) > 1 and points[0] == points[-1]:
        points.pop()
    return points


def load_manifest(output: Path) -> dict:
    path = output / "manifest.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}


def save_feature_manifest(output: Path, updates: dict) -> dict:
    manifest = load_manifest(output)
    features = dict(manifest.get("features", {}))
    features.update({
        "format": "JSONL1", "exporter_version": EXPORTER_VERSION,
        "buildings_file": "buildings.jsonl", "pois_file": "pois.jsonl",
        "poi_tiles_dir": "poi_tiles", "poi_tile_size": TILE_SIZE,
    })
    features.update(updates)
    manifest["features"] = features
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest


def merged_counts(previous: dict, current: Counter[str]) -> dict[str, int]:
    counts = Counter({str(key): int(value) for key, value in previous.items()})
    counts.update(current)
    return dict(sorted(counts.items()))


def print_filter_counts(prefix: str, included: dict[str, int], excluded: dict[str, int]) -> None:
    print(f"[{prefix}] Runtime POI included by category: {json.dumps(included, sort_keys=True)}", flush=True)
    print(f"[{prefix}] Runtime POI excluded by category: {json.dumps(excluded, sort_keys=True)}", flush=True)


class PoiRouteHandler(osmium.SimpleHandler):
    """Direct node+way POI pass over the small POI route cache."""

    def __init__(self, pois_file: TextIO, poi_tiles: TileJsonlWriter) -> None:
        super().__init__()
        self.pois_file = pois_file
        self.poi_tiles = poi_tiles
        self.poi_nodes = 0
        self.poi_ways = 0
        self.scanned_nodes = 0
        self.started = time.monotonic()
        self.next_progress = POI_PROGRESS_INTERVAL

    def node(self, node: osmium.osm.Node) -> None:
        self.scanned_nodes += 1
        if self.scanned_nodes >= self.next_progress:
            elapsed = max(0.001, time.monotonic() - self.started)
            print(f"[pois] nodes={self.scanned_nodes:,} found={self.poi_nodes + self.poi_ways:,} rate={self.scanned_nodes / elapsed:,.0f}/s", flush=True)
            self.next_progress += POI_PROGRESS_INTERVAL
        if not is_poi(node.tags) or not node.location.valid():
            return
        x, y = project(node.lon, node.lat)
        record = {"osm_type": "node", "osm_id": int(node.id), "x": x, "y": y, "tags": tags_dict(node.tags)}
        write_jsonl(self.pois_file, record)
        self.poi_tiles.write(record)
        self.poi_nodes += 1

    def way(self, way: osmium.osm.Way) -> None:
        if not is_poi(way.tags):
            return
        try:
            points = projected_way(way.nodes)
        except osmium.InvalidLocationError:
            return
        if not points:
            return
        x, y = point_average(points)
        record = {"osm_type": "way", "osm_id": int(way.id), "x": x, "y": y, "geometry": points, "tags": tags_dict(way.tags)}
        write_jsonl(self.pois_file, record)
        self.poi_tiles.write(record)
        self.poi_ways += 1


class HeavyFeatureHandler(osmium.SimpleHandler):
    """Compatibility PBF adapter for building areas and relation-only POIs."""

    def __init__(self, buildings_file: TextIO, pois_file: TextIO | None, poi_tiles: TileJsonlWriter | None) -> None:
        super().__init__()
        self.buildings_file = buildings_file
        self.pois_file = pois_file
        self.poi_tiles = poi_tiles
        self.buildings = 0
        self.poi_areas = 0

    def area(self, area: osmium.osm.Area) -> None:
        tags = tags_dict(area.tags)
        polygons: list[dict] = []
        representative_points: list[list[float]] = []
        for outer in area.outer_rings():
            try:
                shell = projected_ring(outer)
                holes = [projected_ring(inner) for inner in area.inner_rings(outer)]
            except osmium.InvalidLocationError:
                continue
            if len(shell) < 3:
                continue
            polygons.append({"outer": shell, "holes": [hole for hole in holes if len(hole) >= 3]})
            representative_points.extend(shell)
        if polygons:
            self.consume(int(area.id), bool(area.from_way()), tags, polygons, representative_points)

    def consume(self, area_id: int, from_way: bool, tags: dict[str, str], polygons: list[dict], points: list[list[float]]) -> None:
        building = tags.get("building") is not None or tags.get("building:part") is not None
        relation_poi = is_poi_tags(tags) and not from_way
        if not building and not relation_poi:
            return
        x, y = point_average(points)
        record = {"osm_type": "area", "osm_id": area_id, "x": x, "y": y, "geometry": polygons, "tags": tags}
        if building:
            write_jsonl(self.buildings_file, record)
            self.buildings += 1
        if relation_poi and self.pois_file is not None and self.poi_tiles is not None:
            write_jsonl(self.pois_file, record)
            self.poi_tiles.write(record)
            self.poi_areas += 1


def _consume_baf(source: Path, handler: HeavyFeatureHandler) -> None:
    for index, fact in enumerate(iter_area_facts(source), 1):
        polygons = fact["geometry"]
        points = [point for polygon in polygons for point in polygon.get("outer", [])]
        if points:
            handler.consume(
                int(fact.get("area_id", fact["osm_id"])), fact.get("osm_type") == "way",
                {str(k): str(v) for k, v in fact["tags"].items()}, polygons, points,
            )
        if index % 250_000 == 0:
            print(f"[buildings] area-facts={index:,} buildings={handler.buildings:,} relation-pois={handler.poi_areas:,}", flush=True)


def build_pois(source: Path, output: Path) -> dict:
    """Build node+way POIs directly from the selected POI route cache."""
    ensure_pbf(source)
    output.mkdir(parents=True, exist_ok=True)
    pois_path = output / "pois.jsonl"
    poi_tiles = TileJsonlWriter(output / "poi_tiles", staged=True)
    started = time.monotonic()
    print_version()
    print(f"[pois] START source={source}", flush=True)
    success = False
    try:
        with pois_path.open("w", encoding="utf-8") as pois_file:
            handler = PoiRouteHandler(pois_file, poi_tiles)
            handler.apply_file(str(source), locations=True)
        poi_tiles.publish()
        success = True
    finally:
        if not success:
            poi_tiles.cleanup()
    included = dict(sorted(poi_tiles.included.items()))
    excluded = dict(sorted(poi_tiles.excluded.items()))
    manifest = save_feature_manifest(output, {
        "poi_nodes": handler.poi_nodes, "poi_ways": handler.poi_ways, "poi_areas": 0,
        "pois_total": handler.poi_nodes + handler.poi_ways,
        "runtime_pois_total": poi_tiles.records,
        "runtime_poi_included_by_category": included,
        "runtime_poi_excluded_by_category": excluded,
        "pois_fast_complete": True, "way_pois_complete": True, "relation_pois_complete": False,
    })
    print(f"[pois] DONE nodes={handler.poi_nodes:,} ways={handler.poi_ways:,} runtime={poi_tiles.records:,} elapsed={time.monotonic() - started:.1f}s", flush=True)
    return manifest


def build_buildings(source: Path, output: Path) -> dict:
    """Build buildings and append relation-only POIs from shared area facts."""
    if not area_source_cache_valid(source):
        ensure_pbf(source)
    output.mkdir(parents=True, exist_ok=True)
    buildings_path = output / "buildings.jsonl"
    pois_path = output / "pois.jsonl"
    poi_tiles = TileJsonlWriter(output / "poi_tiles", staged=False)
    started = time.monotonic()
    print_version()
    print(f"[buildings] START source={source}", flush=True)
    with buildings_path.open("w", encoding="utf-8") as buildings_file, pois_path.open("a", encoding="utf-8") as pois_file:
        handler = HeavyFeatureHandler(buildings_file, pois_file, poi_tiles)
        if area_source_cache_valid(source):
            _consume_baf(source, handler)
        else:
            handler.apply_file(str(source), locations=True)
    poi_tiles.close()
    features = dict(load_manifest(output).get("features", {}))
    poi_nodes = int(features.get("poi_nodes", 0))
    poi_ways = int(features.get("poi_ways", 0))
    total = poi_nodes + poi_ways + handler.poi_areas
    included = merged_counts(features.get("runtime_poi_included_by_category", {}), poi_tiles.included)
    excluded = merged_counts(features.get("runtime_poi_excluded_by_category", {}), poi_tiles.excluded)
    runtime_total = int(features.get("runtime_pois_total", 0)) + poi_tiles.records
    manifest = save_feature_manifest(output, {
        "buildings": handler.buildings, "poi_ways": poi_ways, "poi_areas": handler.poi_areas,
        "pois_total": total, "runtime_pois_total": runtime_total,
        "runtime_poi_included_by_category": included, "runtime_poi_excluded_by_category": excluded,
        "way_pois_complete": True, "relation_pois_complete": True,
        "area_source_shared": area_source_cache_valid(source),
    })
    print(f"[buildings] DONE buildings={handler.buildings:,} relation-pois={handler.poi_areas:,} elapsed={time.monotonic() - started:.1f}s", flush=True)
    return manifest


def build_features(pbf: Path, output: Path) -> dict:
    print("=== BUILD POIS ===", flush=True)
    build_pois(pbf, output)
    print("=== BUILD BUILDINGS / RELATION POIS ===", flush=True)
    return build_buildings(pbf, output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pbf", type=Path, nargs="?")
    parser.add_argument("--output", type=Path, default=Path("world_data"))
    parser.add_argument("--part", choices=("all", "pois", "buildings"), default="all")
    parser.add_argument("--version", action="store_true")
    args = parser.parse_args()
    if args.version:
        print_version()
        return
    if args.pbf is None:
        parser.error("pbf is required unless --version is used")
    if args.part == "pois":
        build_pois(args.pbf, args.output)
    elif args.part == "buildings":
        build_buildings(args.pbf, args.output)
    else:
        build_features(args.pbf, args.output)


if __name__ == "__main__":
    main()
