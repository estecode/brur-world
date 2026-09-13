#!/usr/bin/env python3
"""Build portable BRT1 road tiles from the shared OSM highway source route.

Dependencies:
- osm_route_source.py redirects authoritative Sweden PBF input through the reusable OSM source cache.
- Reads cached highway OSM or small fixture OSM with pyosmium.
"""

from __future__ import annotations

import argparse
import json
import math
import struct
from collections import defaultdict
from pathlib import Path

import osmium

from osm_route_source import resolve_route_source
from world_common import TILE_SIZE, ensure_pbf, project

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
# Far LODs keep progressively more of the same road hierarchy instead of
# switching to a visually different motorway-only map. Geometry is simplified
# offline so distant views stay cheap while near LOD remains full fidelity.
LOD_MAX_CLASS = (4, 5, 6)
LOD_MIN_SPACING = (1200.0, 300.0, 0.0)
SEGMENT = struct.Struct("<Bffff")
HEADER = struct.Struct("<4sI")


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


class RoadHandler(osmium.SimpleHandler):
    def __init__(self) -> None:
        super().__init__()
        self.payloads: list[dict[tuple[int, int], bytearray]] = [defaultdict(bytearray) for _ in range(3)]
        self.counts: list[dict[tuple[int, int], int]] = [defaultdict(int) for _ in range(3)]
        self.min_x = math.inf
        self.min_y = math.inf
        self.max_x = -math.inf
        self.max_y = -math.inf
        self.ways = 0
        self.segments = [0, 0, 0]

    def way(self, way: osmium.osm.Way) -> None:
        road_class = ROAD_CLASS.get(way.tags.get("highway"))
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
                tx = math.floor(((x1 + x2) * 0.5) / TILE_SIZE)
                ty = math.floor(((y1 + y2) * 0.5) / TILE_SIZE)
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


def build_roads(source: Path, output: Path) -> dict:
    source = Path(source)
    output = Path(output)
    ensure_pbf(source)
    output.mkdir(parents=True, exist_ok=True)
    source = resolve_route_source(source, output, "highways")

    handler = RoadHandler()
    print(f"[roads] Reading {source} ...")
    handler.apply_file(str(source), locations=True)
    if handler.ways == 0:
        raise SystemExit("No supported highway ways found")

    for lod in range(3):
        lod_dir = output / f"lod{lod}"
        lod_dir.mkdir(parents=True, exist_ok=True)
        for (tx, ty), payload in handler.payloads[lod].items():
            with (lod_dir / f"{tx}_{ty}.brtile").open("wb") as f:
                f.write(HEADER.pack(b"BRT1", handler.counts[lod][(tx, ty)]))
                f.write(payload)

    origin_x = (handler.min_x + handler.max_x) * 0.5
    origin_y = (handler.min_y + handler.max_y) * 0.5
    manifest_path = output / "manifest.json"
    manifest = {}
    if manifest_path.is_file():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest.update(
        {
            "format": "BRT1",
            "tile_size": TILE_SIZE,
            "origin_x": origin_x,
            "origin_y": origin_y,
            "bounds": [handler.min_x, handler.min_y, handler.max_x, handler.max_y],
            "road_lod_policy": {
                "max_class": list(LOD_MAX_CLASS),
                "min_spacing_m": list(LOD_MIN_SPACING),
            },
            "lods": [
                {"lod": i, "tiles": len(handler.payloads[i]), "segments": handler.segments[i]}
                for i in range(3)
            ],
        }
    )
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    print(f"[roads] Road ways: {handler.ways:,}")
    for lod in range(3):
        print(f"[roads] LOD {lod}: {len(handler.payloads[lod]):,} tiles, {handler.segments[lod]:,} segments")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Path to Sweden .osm.pbf, cached highway .osm, or a small .osm fixture")
    parser.add_argument("--output", type=Path, default=Path("world_data"))
    args = parser.parse_args()
    build_roads(args.source, args.output)


if __name__ == "__main__":
    main()
