#!/usr/bin/env python3
"""Export POI/building data from route caches and shared assembled area facts.

Dependencies:
- Reads selected OSM route caches through pyosmium for node/way POIs.
- Reads BAF1 assembled area facts for relation POIs and buildings.
- Uses poi_filter for deterministic runtime relevance/category decisions.

POI and building outputs are independently owned: rebuilding buildings never
mutates POI output, which is required for directed target invalidation.
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

EXPORTER_VERSION = "poi-v7-directed-targets"
POI_PROGRESS_INTERVAL = 5_000_000


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
        key = (
            math.floor(float(runtime_record["x"]) / TILE_SIZE),
            math.floor(float(runtime_record["y"]) / TILE_SIZE),
        )
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
        return subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"], stderr=subprocess.DEVNULL, text=True
        ).strip()
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
        "osm_type": record["osm_type"],
        "osm_id": record["osm_id"],
        "x": record["x"],
        "y": record["y"],
        "category": category,
        "tags": record["tags"],
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
        "format": "JSONL1",
        "exporter_version": EXPORTER_VERSION,
        "buildings_file": "buildings.jsonl",
        "pois_file": "pois.jsonl",
        "poi_tiles_dir": "poi_tiles",
        "poi_tile_size": TILE_SIZE,
    })
    features.update(updates)
    manifest["features"] = features
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest


class PoiRouteHandler(osmium.SimpleHandler):
    """Direct node+way POI pass over the small selected POI route cache."""

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
            print(
                f"[pois] nodes={self.scanned_nodes:,} found={self.poi_nodes + self.poi_ways:,} "
                f"rate={self.scanned_nodes / elapsed:,.0f}/s",
                flush=True,
            )
            self.next_progress += POI_PROGRESS_INTERVAL
        if not is_poi(node.tags) or not node.location.valid():
            return
        x, y = project(node.lon, node.lat)
        record = {
            "osm_type": "node", "osm_id": int(node.id), "x": x, "y": y,
            "tags": tags_dict(node.tags),
        }
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
        record = {
            "osm_type": "way", "osm_id": int(way.id), "x": x, "y": y,
            "geometry": points, "tags": tags_dict(way.tags),
        }
        write_jsonl(self.pois_file, record)
        self.poi_tiles.write(record)
        self.poi_ways += 1


class RelationPoiHandler(osmium.SimpleHandler):
    def __init__(self, pois_file: TextIO, poi_tiles: TileJsonlWriter) -> None:
        super().__init__()
        self.pois_file = pois_file
        self.poi_tiles = poi_tiles
        self.poi_areas = 0

    def area(self, area: osmium.osm.Area) -> None:
        if area.from_way() or not is_poi(area.tags):
            return
        polygons: list[dict] = []
        points: list[list[float]] = []
        for outer in area.outer_rings():
            try:
                shell = projected_ring(outer)
                holes = [projected_ring(inner) for inner in area.inner_rings(outer)]
            except osmium.InvalidLocationError:
                continue
            if len(shell) < 3:
                continue
            polygons.append({"outer": shell, "holes": [hole for hole in holes if len(hole) >= 3]})
            points.extend(shell)
        if not points:
            return
        self.consume(int(area.id), tags_dict(area.tags), polygons, points)

    def consume(self, area_id: int, tags: dict[str, str], polygons: list[dict], points: list[list[float]]) -> None:
        if not is_poi_tags(tags):
            return
        x, y = point_average(points)
        record = {
            "osm_type": "area", "osm_id": area_id, "x": x, "y": y,
            "geometry": polygons, "tags": tags,
        }
        write_jsonl(self.pois_file, record)
        self.poi_tiles.write(record)
        self.poi_areas += 1


class BuildingHandler(osmium.SimpleHandler):
    def __init__(self, buildings_file: TextIO) -> None:
        super().__init__()
        self.buildings_file = buildings_file
        self.buildings = 0

    def area(self, area: osmium.osm.Area) -> None:
        tags = tags_dict(area.tags)
        if tags.get("building") is None and tags.get("building:part") is None:
            return
        polygons: list[dict] = []
        points: list[list[float]] = []
        for outer in area.outer_rings():
            try:
                shell = projected_ring(outer)
                holes = [projected_ring(inner) for inner in area.inner_rings(outer)]
            except osmium.InvalidLocationError:
                continue
            if len(shell) < 3:
                continue
            polygons.append({"outer": shell, "holes": [hole for hole in holes if len(hole) >= 3]})
            points.extend(shell)
        if points:
            self.consume(int(area.id), tags, polygons, points)

    def consume(self, area_id: int, tags: dict[str, str], polygons: list[dict], points: list[list[float]]) -> None:
        if tags.get("building") is None and tags.get("building:part") is None:
            return
        x, y = point_average(points)
        write_jsonl(self.buildings_file, {
            "osm_type": "area", "osm_id": area_id, "x": x, "y": y,
            "geometry": polygons, "tags": tags,
        })
        self.buildings += 1


def _append_relation_pois(area_source: Path, pois_file: TextIO, poi_tiles: TileJsonlWriter) -> int:
    handler = RelationPoiHandler(pois_file, poi_tiles)
    if area_source_cache_valid(area_source):
        for index, fact in enumerate(iter_area_facts(area_source), 1):
            if fact.get("osm_type") != "relation":
                continue
            tags = {str(k): str(v) for k, v in fact["tags"].items()}
            if not is_poi_tags(tags):
                continue
            polygons = fact["geometry"]
            points = [point for polygon in polygons for point in polygon.get("outer", [])]
            if points:
                handler.consume(int(fact.get("area_id", fact["osm_id"])), tags, polygons, points)
            if index % 250_000 == 0:
                print(f"[pois] area-facts={index:,} relation-pois={handler.poi_areas:,}", flush=True)
    else:
        ensure_pbf(area_source)
        handler.apply_file(str(area_source), locations=True)
    return handler.poi_areas


def _build_buildings_from_source(source: Path, buildings_file: TextIO) -> int:
    handler = BuildingHandler(buildings_file)
    if area_source_cache_valid(source):
        for index, fact in enumerate(iter_area_facts(source), 1):
            tags = {str(k): str(v) for k, v in fact["tags"].items()}
            if tags.get("building") is None and tags.get("building:part") is None:
                continue
            polygons = fact["geometry"]
            points = [point for polygon in polygons for point in polygon.get("outer", [])]
            if points:
                handler.consume(int(fact.get("area_id", fact["osm_id"])), tags, polygons, points)
            if index % 250_000 == 0:
                print(f"[buildings] area-facts={index:,} buildings={handler.buildings:,}", flush=True)
    else:
        ensure_pbf(source)
        handler.apply_file(str(source), locations=True)
    return handler.buildings


def build_pois(source: Path, output: Path, area_source: Path | None = None) -> dict:
    """Build complete POIs; optional area_source supplies relation-only POIs."""
    ensure_pbf(source)
    if area_source is not None and not area_source_cache_valid(area_source):
        ensure_pbf(area_source)
    output.mkdir(parents=True, exist_ok=True)
    pois_path = output / "pois.jsonl"
    poi_tiles = TileJsonlWriter(output / "poi_tiles", staged=True)
    started = time.monotonic()
    print_version()
    print(f"[pois] START source={source} area_source={area_source or 'none'}", flush=True)
    success = False
    try:
        with pois_path.open("w", encoding="utf-8") as pois_file:
            handler = PoiRouteHandler(pois_file, poi_tiles)
            handler.apply_file(str(source), locations=True)
            poi_areas = _append_relation_pois(area_source, pois_file, poi_tiles) if area_source is not None else 0
        poi_tiles.publish()
        success = True
    finally:
        if not success:
            poi_tiles.cleanup()

    included = dict(sorted(poi_tiles.included.items()))
    excluded = dict(sorted(poi_tiles.excluded.items()))
    total = handler.poi_nodes + handler.poi_ways + poi_areas
    manifest = save_feature_manifest(output, {
        "poi_nodes": handler.poi_nodes,
        "poi_ways": handler.poi_ways,
        "poi_areas": poi_areas,
        "pois_total": total,
        "runtime_pois_total": poi_tiles.records,
        "runtime_poi_included_by_category": included,
        "runtime_poi_excluded_by_category": excluded,
        "pois_fast_complete": True,
        "way_pois_complete": True,
        "relation_pois_complete": area_source is not None,
    })
    print(
        f"[pois] DONE nodes={handler.poi_nodes:,} ways={handler.poi_ways:,} relation={poi_areas:,} "
        f"runtime={poi_tiles.records:,} elapsed={time.monotonic() - started:.1f}s",
        flush=True,
    )
    return manifest


def build_buildings(source: Path, output: Path) -> dict:
    """Build authoritative building JSONL only; POI output is owned elsewhere."""
    if not area_source_cache_valid(source):
        ensure_pbf(source)
    output.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    print_version()
    print(f"[buildings] START source={source}", flush=True)
    with (output / "buildings.jsonl").open("w", encoding="utf-8") as buildings_file:
        buildings = _build_buildings_from_source(source, buildings_file)
    manifest = save_feature_manifest(output, {
        "buildings": buildings,
        "area_source_shared": area_source_cache_valid(source),
    })
    print(f"[buildings] DONE buildings={buildings:,} elapsed={time.monotonic() - started:.1f}s", flush=True)
    return manifest


def build_features(pbf: Path, output: Path) -> dict:
    print("=== BUILD POIS ===", flush=True)
    build_pois(pbf, output, pbf)
    print("=== BUILD BUILDINGS ===", flush=True)
    return build_buildings(pbf, output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pbf", type=Path, nargs="?")
    parser.add_argument("--output", type=Path, default=Path("world_data"))
    parser.add_argument("--part", choices=("all", "pois", "buildings"), default="all")
    parser.add_argument("--area-source", type=Path)
    parser.add_argument("--version", action="store_true")
    args = parser.parse_args()
    if args.version:
        print_version()
        return
    if args.pbf is None:
        parser.error("pbf is required unless --version is used")
    if args.part == "pois":
        build_pois(args.pbf, args.output, args.area_source)
    elif args.part == "buildings":
        build_buildings(args.pbf, args.output)
    else:
        build_features(args.pbf, args.output)


if __name__ == "__main__":
    main()
