#!/usr/bin/env python3
"""Build portable BRT1 road centerlines plus derived BRS1 road-surface tiles."""
from __future__ import annotations

import argparse
import json
import math
import struct
from collections import defaultdict
from pathlib import Path

import osmium

from highway_facts import iter_highway_ways, projected_points
from road_surface_mesh import RoadSurfaceAccumulator, SurfaceWay, grade_from_tags
from world_common import TILE_SIZE, ensure_pbf, project

ROAD_CLASS = {
    "motorway": 0, "motorway_link": 0, "trunk": 1, "trunk_link": 1,
    "primary": 2, "primary_link": 2, "secondary": 3, "secondary_link": 3,
    "tertiary": 4, "tertiary_link": 4, "residential": 5, "unclassified": 5,
    "living_street": 6, "service": 6,
}
LOD_MAX_CLASS = (4, 5, 6)
LOD_MIN_SPACING = (1200.0, 300.0, 0.0)
SEGMENT = struct.Struct("<Bffff")
HEADER = struct.Struct("<4sI")


def thin(points: list[tuple[float,float]], min_spacing: float) -> list[tuple[float,float]]:
    if min_spacing <= 0.0 or len(points) <= 2: return points
    out = [points[0]]; last_x, last_y = points[0]; min_sq = min_spacing * min_spacing
    for x, y in points[1:-1]:
        dx, dy = x-last_x, y-last_y
        if dx*dx + dy*dy >= min_sq:
            out.append((x,y)); last_x, last_y = x,y
    out.append(points[-1]); return out


class RoadAccumulator:
    def __init__(self) -> None:
        self.payloads: list[dict[tuple[int,int],bytearray]] = [defaultdict(bytearray) for _ in range(3)]
        self.counts: list[dict[tuple[int,int],int]] = [defaultdict(int) for _ in range(3)]
        self.surfaces = [RoadSurfaceAccumulator(TILE_SIZE) for _ in range(3)]
        self.min_x = math.inf; self.min_y = math.inf; self.max_x = -math.inf; self.max_y = -math.inf
        self.ways = 0; self.segments = [0,0,0]

    def add_way(self, points: list[tuple[float,float]], tags) -> None:
        road_class = ROAD_CLASS.get(str(tags.get("highway") or ""))
        if road_class is None or len(points) < 2: return
        self.ways += 1; grade = grade_from_tags(tags)
        for x,y in points:
            self.min_x=min(self.min_x,x); self.min_y=min(self.min_y,y); self.max_x=max(self.max_x,x); self.max_y=max(self.max_y,y)
        for lod, max_class in enumerate(LOD_MAX_CLASS):
            if road_class > max_class: continue
            lod_points = thin(points, LOD_MIN_SPACING[lod])
            if len(lod_points) < 2: continue
            self.surfaces[lod].add_way(SurfaceWay(tuple(lod_points), road_class, grade))
            for (x1,y1),(x2,y2) in zip(lod_points,lod_points[1:]):
                tx=math.floor(((x1+x2)*0.5)/TILE_SIZE); ty=math.floor(((y1+y2)*0.5)/TILE_SIZE)
                self.payloads[lod][(tx,ty)].extend(SEGMENT.pack(road_class,x1-tx*TILE_SIZE,y1-ty*TILE_SIZE,x2-tx*TILE_SIZE,y2-ty*TILE_SIZE))
                self.counts[lod][(tx,ty)] += 1; self.segments[lod] += 1


class RoadHandler(osmium.SimpleHandler):
    def __init__(self, accumulator: RoadAccumulator) -> None:
        super().__init__(); self.accumulator = accumulator
    def way(self, way: osmium.osm.Way) -> None:
        try: points = [project(node.lon,node.lat) for node in way.nodes]
        except osmium.InvalidLocationError: return
        self.accumulator.add_way(points, way.tags)


def build_roads(source: Path, output: Path) -> dict:
    source = Path(source); output = Path(output); output.mkdir(parents=True, exist_ok=True)
    accumulator = RoadAccumulator(); print(f"[roads] Reading {source} ...", flush=True)
    if source.suffix == ".brfacts":
        for index, way in enumerate(iter_highway_ways(source), 1):
            accumulator.add_way(projected_points(way), way.tags)
            if index % 250_000 == 0: print(f"[roads] source-facts={index:,} supported={accumulator.ways:,}", flush=True)
    else:
        ensure_pbf(source); RoadHandler(accumulator).apply_file(str(source), locations=True)
    if accumulator.ways == 0: raise SystemExit("No supported highway ways found")

    surface_stats: list[dict[str,int]] = []
    for lod in range(3):
        lod_dir = output / f"lod{lod}"; lod_dir.mkdir(parents=True, exist_ok=True)
        for (tx,ty), payload in accumulator.payloads[lod].items():
            with (lod_dir / f"{tx}_{ty}.brtile").open("wb") as f:
                f.write(HEADER.pack(b"BRT1", accumulator.counts[lod][(tx,ty)])); f.write(payload)
        stats = accumulator.surfaces[lod].write(output / "road_surfaces" / f"lod{lod}"); surface_stats.append(stats)

    origin_x=(accumulator.min_x+accumulator.max_x)*0.5; origin_y=(accumulator.min_y+accumulator.max_y)*0.5
    manifest_path=output/"manifest.json"
    manifest=json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.is_file() else {}
    manifest.update({
        "format":"BRT1", "road_surface_format":"BRS1", "road_surface_dir":"road_surfaces", "tile_size":TILE_SIZE,
        "origin_x":origin_x, "origin_y":origin_y, "bounds":[accumulator.min_x,accumulator.min_y,accumulator.max_x,accumulator.max_y],
        "road_lod_policy":{"max_class":list(LOD_MAX_CLASS),"min_spacing_m":list(LOD_MIN_SPACING)},
        "lods":[{"lod":i,"tiles":len(accumulator.payloads[i]),"segments":accumulator.segments[i]} for i in range(3)],
        "road_surface_lods":[{"lod":i,"tiles":surface_stats[i]["tiles"],"triangles":surface_stats[i]["triangles"],"bytes":surface_stats[i]["bytes"]} for i in range(3)],
    })
    manifest_path.write_text(json.dumps(manifest,indent=2),encoding="utf-8")
    print(f"[roads] Road ways: {accumulator.ways:,}", flush=True)
    return manifest


def main() -> None:
    parser=argparse.ArgumentParser(); parser.add_argument("source",type=Path); parser.add_argument("--output",type=Path,default=Path("world_data")); args=parser.parse_args(); build_roads(args.source,args.output)


if __name__ == "__main__": main()
