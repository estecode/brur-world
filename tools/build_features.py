#!/usr/bin/env python3
"""Export OSM POIs quickly, then build heavier building/relation areas separately."""

from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import time
from collections import OrderedDict
from pathlib import Path
from typing import TextIO

import osmium

from world_common import TILE_SIZE, ensure_pbf, project

POI_KEYS = {
    "amenity", "shop", "tourism", "leisure", "office", "healthcare", "emergency",
    "public_transport", "railway", "aeroway", "craft", "historic", "sport", "club",
    "man_made", "information", "advertising",
}
SPECIAL_HIGHWAY_POIS = {"speed_camera", "services", "rest_area", "bus_stop", "elevator"}


class TileJsonlWriter:
    """Write POI tile JSONL with a small LRU of open files."""

    def __init__(self, directory: Path, max_open: int = 32, staged: bool = True) -> None:
        self.directory = directory
        self.max_open = max_open
        self.files: OrderedDict[tuple[int, int], TextIO] = OrderedDict()
        self.records = 0
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
        key = (math.floor(float(record["x"]) / TILE_SIZE), math.floor(float(record["y"]) / TILE_SIZE))
        file = self.files.pop(key, None)
        if file is None:
            file = (self.write_directory / f"{key[0]}_{key[1]}.jsonl").open("a", encoding="utf-8")
        self.files[key] = file
        write_jsonl(file, record)
        self.records += 1
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
            try:
                shutil.rmtree(stale)
            except OSError as exc:
                print(f"[features] Warning: could not remove stale POI tiles {stale}: {exc}")

    def cleanup(self) -> None:
        self.close()
        if not self.staged or self.published or not self.write_directory.exists():
            return
        try:
            shutil.rmtree(self.write_directory)
        except OSError as exc:
            print(f"[features] Warning: could not remove staging directory {self.write_directory}: {exc}")


def tags_dict(tags: osmium.osm.TagList) -> dict[str, str]:
    return {tag.k: tag.v for tag in tags}


def is_poi(tags: osmium.osm.TagList) -> bool:
    if any(tags.get(key) is not None for key in POI_KEYS):
        return True
    if tags.get("highway") in SPECIAL_HIGHWAY_POIS:
        return True
    if tags.get("enforcement") is not None or tags.get("surveillance") is not None:
        return True
    return any(tag.k.startswith("camera:") for tag in tags)


def write_jsonl(file: TextIO, record: dict) -> None:
    file.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")


def runtime_poi_record(record: dict) -> dict:
    return {"osm_type": record["osm_type"], "osm_id": record["osm_id"], "x": record["x"], "y": record["y"], "tags": record["tags"]}


def point_average(points: list[list[float]]) -> tuple[float, float]:
    return (sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points))


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
        "buildings_file": "buildings.jsonl",
        "pois_file": "pois.jsonl",
        "poi_tiles_dir": "poi_tiles",
        "poi_tile_size": TILE_SIZE,
    })
    features.update(updates)
    manifest["features"] = features
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest


class PoiScanHandler(osmium.SimpleHandler):
    """First cheap scan: write node POIs and remember only POI way node refs."""

    def __init__(self, pois_file: TextIO, poi_tiles: TileJsonlWriter) -> None:
        super().__init__()
        self.pois_file = pois_file
        self.poi_tiles = poi_tiles
        self.poi_nodes = 0
        self.poi_ways: list[tuple[int, list[int], dict[str, str]]] = []
        self.needed_node_ids: set[int] = set()

    def node(self, node: osmium.osm.Node) -> None:
        if not is_poi(node.tags) or not node.location.valid():
            return
        x, y = project(node.lon, node.lat)
        record = {"osm_type": "node", "osm_id": int(node.id), "x": x, "y": y, "tags": tags_dict(node.tags)}
        write_jsonl(self.pois_file, record)
        self.poi_tiles.write(runtime_poi_record(record))
        self.poi_nodes += 1

    def way(self, way: osmium.osm.Way) -> None:
        if not is_poi(way.tags):
            return
        node_ids = [int(node.ref) for node in way.nodes]
        if not node_ids:
            return
        self.poi_ways.append((int(way.id), node_ids, tags_dict(way.tags)))
        self.needed_node_ids.update(node_ids)


class NeededNodeHandler(osmium.SimpleHandler):
    """Second cheap scan: resolve coordinates only for nodes used by POI ways."""

    def __init__(self, needed: set[int]) -> None:
        super().__init__()
        self.needed = needed
        self.locations: dict[int, tuple[float, float]] = {}

    def node(self, node: osmium.osm.Node) -> None:
        node_id = int(node.id)
        if node_id not in self.needed or not node.location.valid():
            return
        self.locations[node_id] = project(node.lon, node.lat)


class AreaHandler(osmium.SimpleHandler):
    """Heavy pass: building footprints plus POIs that exist only as relations."""

    def __init__(self, buildings_file: TextIO, pois_file: TextIO, poi_tiles: TileJsonlWriter) -> None:
        super().__init__()
        self.buildings_file = buildings_file
        self.pois_file = pois_file
        self.poi_tiles = poi_tiles
        self.buildings = 0
        self.poi_areas = 0

    def area(self, area: osmium.osm.Area) -> None:
        tags = area.tags
        building = tags.get("building") is not None or tags.get("building:part") is not None
        relation_poi = is_poi(tags) and not area.from_way()
        if not building and not relation_poi:
            return
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
        if not polygons:
            return
        x, y = point_average(representative_points)
        record = {"osm_type": "area", "osm_id": int(area.id), "x": x, "y": y, "geometry": polygons, "tags": tags_dict(tags)}
        if building:
            write_jsonl(self.buildings_file, record)
            self.buildings += 1
        if relation_poi:
            write_jsonl(self.pois_file, record)
            self.poi_tiles.write(runtime_poi_record(record))
            self.poi_areas += 1


def build_pois(pbf: Path, output: Path) -> dict:
    """Build node + way POIs without pyosmium's expensive global location index."""
    ensure_pbf(pbf)
    output.mkdir(parents=True, exist_ok=True)
    pois_path = output / "pois.jsonl"
    poi_tiles_path = output / "poi_tiles"
    poi_tiles = TileJsonlWriter(poi_tiles_path, staged=True)
    started = time.monotonic()
    print(f"[pois] Reading {pbf} ...")
    print(f"[pois] Pass 1/2: node POIs + POI way refs, max open tile files: {poi_tiles.max_open}")
    success = False
    try:
        with pois_path.open("w", encoding="utf-8") as pois_file:
            scan = PoiScanHandler(pois_file, poi_tiles)
            scan.apply_file(str(pbf), locations=False)
            print(f"[pois] Pass 1 complete in {time.monotonic() - started:.1f}s; resolving {len(scan.needed_node_ids):,} referenced nodes")
            resolver = NeededNodeHandler(scan.needed_node_ids)
            resolver.apply_file(str(pbf), locations=False)
            way_count = 0
            for way_id, node_ids, tags in scan.poi_ways:
                points: list[list[float]] = []
                for node_id in node_ids:
                    location = resolver.locations.get(node_id)
                    if location is not None:
                        points.append([location[0], location[1]])
                if not points:
                    continue
                x, y = point_average(points)
                record = {"osm_type": "way", "osm_id": way_id, "x": x, "y": y, "geometry": points, "tags": tags}
                write_jsonl(pois_file, record)
                poi_tiles.write(runtime_poi_record(record))
                way_count += 1
        poi_tiles.publish()
        success = True
    finally:
        if not success:
            poi_tiles.cleanup()

    total = scan.poi_nodes + way_count
    manifest = save_feature_manifest(output, {
        "poi_nodes": scan.poi_nodes,
        "poi_ways": way_count,
        "poi_areas": 0,
        "pois_total": total,
        "pois_fast_complete": True,
        "relation_pois_complete": False,
    })
    print(f"[pois] POIs ready: {total:,} (nodes={scan.poi_nodes:,}, ways={way_count:,})")
    print(f"[pois] Runtime POI records: {poi_tiles.records:,}")
    print(f"[pois] Completed in {time.monotonic() - started:.1f}s")
    return manifest


def build_buildings(pbf: Path, output: Path) -> dict:
    ensure_pbf(pbf)
    output.mkdir(parents=True, exist_ok=True)
    buildings_path = output / "buildings.jsonl"
    pois_path = output / "pois.jsonl"
    poi_tiles = TileJsonlWriter(output / "poi_tiles", staged=False)
    started = time.monotonic()
    print(f"[buildings] Reading {pbf} ...")
    print("[buildings] Heavy area pass: building footprints + relation-only POIs")
    with buildings_path.open("w", encoding="utf-8") as buildings_file, pois_path.open("a", encoding="utf-8") as pois_file:
        handler = AreaHandler(buildings_file, pois_file, poi_tiles)
        handler.apply_file(str(pbf), locations=True)
    poi_tiles.close()
    features = dict(load_manifest(output).get("features", {}))
    poi_nodes = int(features.get("poi_nodes", 0))
    poi_ways = int(features.get("poi_ways", 0))
    total = poi_nodes + poi_ways + handler.poi_areas
    manifest = save_feature_manifest(output, {
        "buildings": handler.buildings,
        "poi_areas": handler.poi_areas,
        "pois_total": total,
        "relation_pois_complete": True,
    })
    print(f"[buildings] Buildings: {handler.buildings:,}")
    print(f"[buildings] Relation POIs appended: {handler.poi_areas:,}")
    print(f"[buildings] Completed in {time.monotonic() - started:.1f}s")
    return manifest


def build_features(pbf: Path, output: Path) -> dict:
    print("=== BUILD POIS (FAST) ===")
    build_pois(pbf, output)
    print()
    print("=== BUILD BUILDINGS / RELATION POIS (HEAVY) ===")
    return build_buildings(pbf, output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pbf", type=Path)
    parser.add_argument("--output", type=Path, default=Path("world_data"))
    parser.add_argument("--part", choices=("all", "pois", "buildings"), default="all")
    args = parser.parse_args()
    if args.part == "pois":
        build_pois(args.pbf, args.output)
    elif args.part == "buildings":
        build_buildings(args.pbf, args.output)
    else:
        build_features(args.pbf, args.output)


if __name__ == "__main__":
    main()
