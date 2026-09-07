#!/usr/bin/env python3
"""Export raw OSM buildings and POIs for later gameplay/world analysis."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import TextIO

import osmium

from world_common import ensure_pbf, project

POI_KEYS = {
    "amenity",
    "shop",
    "tourism",
    "leisure",
    "office",
    "healthcare",
    "emergency",
    "public_transport",
    "railway",
    "aeroway",
    "craft",
    "historic",
    "sport",
    "club",
    "man_made",
}


def tags_dict(tags: osmium.osm.TagList) -> dict[str, str]:
    """Keep the original OSM tags intact so we can analyse them later."""
    return {tag.k: tag.v for tag in tags}


def is_poi(tags: osmium.osm.TagList) -> bool:
    return any(tags.get(key) is not None for key in POI_KEYS)


def projected_ring(ring: osmium.osm.NodeRefList) -> list[list[float]]:
    points: list[list[float]] = []
    for node in ring:
        if not node.location.valid():
            continue
        x, y = project(node.lon, node.lat)
        points.append([x, y])
    if len(points) > 1 and points[0] == points[-1]:
        points.pop()
    return points


def projected_way(nodes: osmium.osm.WayNodeList) -> list[list[float]]:
    points: list[list[float]] = []
    for node in nodes:
        if not node.location.valid():
            continue
        x, y = project(node.lon, node.lat)
        points.append([x, y])
    return points


def write_jsonl(file: TextIO, record: dict) -> None:
    file.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")


class FeatureHandler(osmium.SimpleHandler):
    def __init__(self, buildings_file: TextIO, pois_file: TextIO) -> None:
        super().__init__()
        self.buildings_file = buildings_file
        self.pois_file = pois_file
        self.buildings = 0
        self.poi_nodes = 0
        self.poi_ways = 0
        self.poi_areas = 0

    def node(self, node: osmium.osm.Node) -> None:
        if not is_poi(node.tags) or not node.location.valid():
            return
        x, y = project(node.lon, node.lat)
        write_jsonl(
            self.pois_file,
            {
                "osm_type": "node",
                "osm_id": int(node.id),
                "x": x,
                "y": y,
                "tags": tags_dict(node.tags),
            },
        )
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
        write_jsonl(
            self.pois_file,
            {
                "osm_type": "way",
                "osm_id": int(way.id),
                "geometry": points,
                "tags": tags_dict(way.tags),
            },
        )
        self.poi_ways += 1

    def area(self, area: osmium.osm.Area) -> None:
        tags = area.tags
        building = tags.get("building") is not None or tags.get("building:part") is not None
        poi = is_poi(tags)
        if not building and not poi:
            return

        polygons: list[dict] = []
        for outer in area.outer_rings():
            try:
                shell = projected_ring(outer)
                holes = [projected_ring(inner) for inner in area.inner_rings(outer)]
            except osmium.InvalidLocationError:
                continue
            if len(shell) < 3:
                continue
            polygons.append(
                {
                    "outer": shell,
                    "holes": [hole for hole in holes if len(hole) >= 3],
                }
            )

        if not polygons:
            return

        record = {
            "osm_type": "area",
            "osm_id": int(area.id),
            "geometry": polygons,
            "tags": tags_dict(tags),
        }

        if building:
            write_jsonl(self.buildings_file, record)
            self.buildings += 1
        if poi:
            write_jsonl(self.pois_file, record)
            self.poi_areas += 1


def build_features(pbf: Path, output: Path) -> dict:
    ensure_pbf(pbf)
    output.mkdir(parents=True, exist_ok=True)

    buildings_path = output / "buildings.jsonl"
    pois_path = output / "pois.jsonl"

    print(f"[features] Reading {pbf} ...")
    with buildings_path.open("w", encoding="utf-8") as buildings_file, pois_path.open(
        "w", encoding="utf-8"
    ) as pois_file:
        handler = FeatureHandler(buildings_file, pois_file)
        handler.apply_file(str(pbf), locations=True)

    counts = {
        "buildings": handler.buildings,
        "poi_nodes": handler.poi_nodes,
        "poi_ways": handler.poi_ways,
        "poi_areas": handler.poi_areas,
        "pois_total": handler.poi_nodes + handler.poi_ways + handler.poi_areas,
    }

    manifest_path = output / "manifest.json"
    manifest: dict = {}
    if manifest_path.is_file():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["features"] = {
        "format": "JSONL1",
        "buildings_file": buildings_path.name,
        "pois_file": pois_path.name,
        **counts,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    print(f"[features] Buildings: {handler.buildings:,}")
    print(
        "[features] POIs: "
        f"{counts['pois_total']:,} "
        f"(nodes={handler.poi_nodes:,}, ways={handler.poi_ways:,}, areas={handler.poi_areas:,})"
    )
    print(f"[features] Wrote {buildings_path} and {pois_path}")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pbf", type=Path)
    parser.add_argument("--output", type=Path, default=Path("world_data"))
    args = parser.parse_args()
    build_features(args.pbf, args.output)


if __name__ == "__main__":
    main()
