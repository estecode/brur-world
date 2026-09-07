#!/usr/bin/env python3
"""Build portable road tiles and a robust triangulated OSM background map for the Godot POC."""

from __future__ import annotations

import argparse
import json
import math
import struct
from collections import defaultdict
from pathlib import Path

import osmium
from shapely import constrained_delaunay_triangles, make_valid
from shapely.geometry import Polygon

TILE_SIZE = 32_000.0
EARTH_RADIUS = 6_378_137.0
ROAD_CLASS = {
    "motorway": 0,
    "motorway_link": 0,
    "trunk": 1,
    "trunk_link": 1,
    "primary": 2,
    "primary_link": 2,
    "secondary": 3,
    "secondary_link": 3,
    "tertiary": 4,
    "tertiary_link": 4,
    "residential": 5,
    "unclassified": 5,
    "living_street": 6,
    "service": 6,
}
LOD_MAX_CLASS = (1, 3, 6)
LOD_MIN_SPACING = (400.0, 100.0, 0.0)
SEGMENT = struct.Struct("<Bffff")
HEADER = struct.Struct("<4sI")
BACKGROUND_HEADER = struct.Struct("<4sI")
BACKGROUND_TRIANGLE = struct.Struct("<Bffffff")

LAND = 0
FARMLAND = 1
FOREST = 2
URBAN = 3
WATER = 4


def project(lon: float, lat: float) -> tuple[float, float]:
    """Web Mercator meters, shared by roads and background geometry."""
    lat = max(-85.05112878, min(85.05112878, lat))
    x = EARTH_RADIUS * math.radians(lon)
    y = EARTH_RADIUS * math.log(math.tan(math.pi / 4.0 + math.radians(lat) / 2.0))
    return x, y


def thin(points: list[tuple[float, float]], min_spacing: float) -> list[tuple[float, float]]:
    if min_spacing <= 0.0 or len(points) <= 2:
        return points
    out = [points[0]]
    last_x, last_y = points[0]
    min_sq = min_spacing * min_spacing
    for x, y in points[1:-1]:
        dx, dy = x - last_x, y - last_y
        if dx * dx + dy * dy >= min_sq:
            out.append((x, y))
            last_x, last_y = x, y
    out.append(points[-1])
    return out


def background_class(tags: osmium.osm.TagList) -> int | None:
    if (
        tags.get("boundary") == "administrative"
        and tags.get("admin_level") == "2"
        and (tags.get("ISO3166-1") == "SE" or tags.get("name") in {"Sverige", "Sweden"})
    ):
        return LAND

    natural = tags.get("natural")
    landuse = tags.get("landuse")
    waterway = tags.get("waterway")

    if natural == "water" or waterway == "riverbank" or landuse in {"reservoir", "basin"}:
        return WATER
    if natural == "wood" or landuse == "forest":
        return FOREST
    if landuse in {"farmland", "farmyard", "meadow", "grass", "orchard", "vineyard"}:
        return FARMLAND
    if landuse in {"residential", "commercial", "industrial", "retail"}:
        return URBAN
    return None


def background_spacing(kind: int) -> float:
    if kind == LAND:
        return 650.0
    if kind == WATER:
        return 140.0
    if kind in {FOREST, FARMLAND}:
        return 220.0
    return 100.0


def background_min_bbox_area(kind: int) -> float:
    if kind == LAND:
        return 0.0
    if kind == WATER:
        return 500_000.0
    if kind == URBAN:
        return 1_000_000.0
    return 4_000_000.0


def ring_points(ring: osmium.osm.NodeRefList) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    for node in ring:
        if not node.location.valid():
            continue
        points.append(project(node.lon, node.lat))
    if len(points) > 1 and points[0] == points[-1]:
        points.pop()
    return points


class WorldHandler(osmium.SimpleHandler):
    def __init__(self) -> None:
        super().__init__()
        self.payloads: list[dict[tuple[int, int], bytearray]] = [defaultdict(bytearray) for _ in range(3)]
        self.counts: list[dict[tuple[int, int], int]] = [defaultdict(int) for _ in range(3)]
        self.background_payload = bytearray()
        self.background_triangles = 0
        self.background_counts = [0, 0, 0, 0, 0]
        self.min_x = math.inf
        self.min_y = math.inf
        self.max_x = -math.inf
        self.max_y = -math.inf
        self.ways = 0
        self.segments = [0, 0, 0]

    def way(self, way: osmium.osm.Way) -> None:
        highway = way.tags.get("highway")
        road_class = ROAD_CLASS.get(highway)
        if road_class is None:
            return
        try:
            points = [project(node.lon, node.lat) for node in way.nodes]
        except osmium.InvalidLocationError:
            return
        if len(points) < 2:
            return
        self.ways += 1
        for x, y in points:
            self.min_x = min(self.min_x, x)
            self.min_y = min(self.min_y, y)
            self.max_x = max(self.max_x, x)
            self.max_y = max(self.max_y, y)

        for lod, max_class in enumerate(LOD_MAX_CLASS):
            if road_class > max_class:
                continue
            lod_points = thin(points, LOD_MIN_SPACING[lod])
            for (x1, y1), (x2, y2) in zip(lod_points, lod_points[1:]):
                mid_x = (x1 + x2) * 0.5
                mid_y = (y1 + y2) * 0.5
                tx = math.floor(mid_x / TILE_SIZE)
                ty = math.floor(mid_y / TILE_SIZE)
                self.payloads[lod][(tx, ty)].extend(
                    SEGMENT.pack(
                        road_class,
                        x1 - tx * TILE_SIZE,
                        y1 - ty * TILE_SIZE,
                        x2 - tx * TILE_SIZE,
                        y2 - ty * TILE_SIZE,
                    )
                )
                self.counts[lod][(tx, ty)] += 1
                self.segments[lod] += 1

    def area(self, area: osmium.osm.Area) -> None:
        kind = background_class(area.tags)
        if kind is None:
            return

        for outer in area.outer_rings():
            try:
                shell = ring_points(outer)
                holes = [ring_points(inner) for inner in area.inner_rings(outer)]
            except osmium.InvalidLocationError:
                continue
            if len(shell) < 3:
                continue
            holes = [hole for hole in holes if len(hole) >= 3]

            polygon = Polygon(shell, holes)
            if polygon.is_empty:
                continue
            min_x, min_y, max_x, max_y = polygon.bounds
            if (max_x - min_x) * (max_y - min_y) < background_min_bbox_area(kind):
                continue

            geometry = make_valid(polygon)
            geometry = geometry.simplify(background_spacing(kind), preserve_topology=True)
            if geometry.is_empty:
                continue

            triangles = constrained_delaunay_triangles(geometry)
            written_for_area = 0
            for triangle in triangles.geoms:
                coords = list(triangle.exterior.coords)
                if len(coords) < 4:
                    continue
                (x1, y1), (x2, y2), (x3, y3) = coords[:3]
                self.background_payload.extend(
                    BACKGROUND_TRIANGLE.pack(kind, x1, y1, x2, y2, x3, y3)
                )
                self.background_triangles += 1
                written_for_area += 1
            if written_for_area > 0:
                self.background_counts[kind] += 1


def write_background(handler: WorldHandler, output: Path) -> None:
    path = output / "background.brmap"
    with path.open("wb") as f:
        f.write(BACKGROUND_HEADER.pack(b"BRM2", handler.background_triangles))
        f.write(handler.background_payload)


def write_world(handler: WorldHandler, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    for lod in range(3):
        lod_dir = output / f"lod{lod}"
        lod_dir.mkdir(parents=True, exist_ok=True)
        for (tx, ty), payload in handler.payloads[lod].items():
            path = lod_dir / f"{tx}_{ty}.brtile"
            with path.open("wb") as f:
                f.write(HEADER.pack(b"BRT1", handler.counts[lod][(tx, ty)]))
                f.write(payload)

    write_background(handler, output)

    origin_x = (handler.min_x + handler.max_x) * 0.5
    origin_y = (handler.min_y + handler.max_y) * 0.5
    manifest = {
        "format": "BRT1",
        "background_format": "BRM2",
        "tile_size": TILE_SIZE,
        "origin_x": origin_x,
        "origin_y": origin_y,
        "bounds": [handler.min_x, handler.min_y, handler.max_x, handler.max_y],
        "lods": [
            {"lod": i, "tiles": len(handler.payloads[i]), "segments": handler.segments[i]}
            for i in range(3)
        ],
        "background": {
            "triangles": handler.background_triangles,
            "areas": {
                "land": handler.background_counts[LAND],
                "farmland": handler.background_counts[FARMLAND],
                "forest": handler.background_counts[FOREST],
                "urban": handler.background_counts[URBAN],
                "water": handler.background_counts[WATER],
            },
        },
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pbf", type=Path, help="Path to an .osm.pbf file")
    parser.add_argument("--output", type=Path, default=Path("world_data"))
    args = parser.parse_args()
    if not args.pbf.is_file():
        raise SystemExit(f"PBF not found: {args.pbf}")

    handler = WorldHandler()
    print(f"Reading {args.pbf} ...")
    handler.apply_file(str(args.pbf), locations=True)
    if handler.ways == 0:
        raise SystemExit("No supported highway ways found")
    print(f"Road ways: {handler.ways:,}")
    write_world(handler, args.output)
    for lod in range(3):
        print(f"LOD {lod}: {len(handler.payloads[lod]):,} tiles, {handler.segments[lod]:,} segments")
    print(
        "Background areas: "
        f"land={handler.background_counts[LAND]:,}, "
        f"farmland={handler.background_counts[FARMLAND]:,}, "
        f"forest={handler.background_counts[FOREST]:,}, "
        f"urban={handler.background_counts[URBAN]:,}, "
        f"water={handler.background_counts[WATER]:,}"
    )
    print(f"Background triangles: {handler.background_triangles:,}")
    print(f"Done: {args.output / 'manifest.json'}")


if __name__ == "__main__":
    main()
