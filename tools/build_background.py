#!/usr/bin/env python3
"""Build the BRM2 triangulated OSM background map from PBF or BAF1 facts.

Ocean remains the runtime base plane. LAND is solved offline from directed OSM
coastline facts; the national administrative area is used only as a clipping
boundary that closes the finite Sweden build domain. It is never classified as
land on its own.
"""

from __future__ import annotations

import argparse
import json
import math
import struct
import time
from pathlib import Path

import osmium
from shapely import constrained_delaunay_triangles, make_valid
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import polygonize, unary_union
from shapely.strtree import STRtree

from area_source_cache import area_source_cache_valid, iter_area_facts
from world_common import TILE_SIZE, ensure_pbf, project

BACKGROUND_HEADER = struct.Struct("<4sI")
BACKGROUND_TRIANGLE = struct.Struct("<Bffffff")

LAND = 0
FARMLAND = 1
FOREST = 2
URBAN = 3
WATER = 4
WATER_NATURAL = {"water"}
WATER_LANDUSE = {"reservoir"}
COAST_SEED_OFFSET_M = 25.0


def _tag_get(tags, key: str):
    return tags.get(key)


def is_admin_domain(tags) -> bool:
    return _tag_get(tags, "boundary") == "administrative" and _tag_get(tags, "admin_level") == "2"


def background_class(tags) -> int | None:
    # Administrative boundaries are clipping material only. OSM coastline owns
    # the land/ocean classification.
    if is_admin_domain(tags):
        return None
    natural = _tag_get(tags, "natural")
    landuse = _tag_get(tags, "landuse")
    if natural in WATER_NATURAL or landuse in WATER_LANDUSE:
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


def way_points(nodes: osmium.osm.WayNodeList) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    for node in nodes:
        if not node.location.valid():
            continue
        points.append(project(node.lon, node.lat))
    return points


def iter_polygons(geometry):
    if geometry.is_empty:
        return
    if geometry.geom_type == "Polygon":
        yield geometry
        return
    if hasattr(geometry, "geoms"):
        for child in geometry.geoms:
            yield from iter_polygons(child)


def _raw_polygons(polygons: list[dict]) -> list[Polygon]:
    result: list[Polygon] = []
    for raw in polygons:
        shell = [tuple(point) for point in raw.get("outer", [])]
        holes = [[tuple(point) for point in hole] for hole in raw.get("holes", [])]
        if len(shell) < 3:
            continue
        polygon = Polygon(shell, [hole for hole in holes if len(hole) >= 3])
        if polygon.is_empty:
            continue
        geometry = polygon if polygon.is_valid else make_valid(polygon)
        result.extend(part for part in iter_polygons(geometry) if not part.is_empty and part.area > 0.0)
    return result


def _left_seed_points(line: LineString, domain) -> list[Point]:
    seeds: list[Point] = []
    coords = list(line.coords)
    for index in range(len(coords) - 1):
        x1, y1 = coords[index]
        x2, y2 = coords[index + 1]
        dx = x2 - x1
        dy = y2 - y1
        length = math.hypot(dx, dy)
        if length <= 0.01:
            continue
        midpoint_x = (x1 + x2) * 0.5
        midpoint_y = (y1 + y2) * 0.5
        seed = Point(
            midpoint_x - (dy / length) * COAST_SEED_OFFSET_M,
            midpoint_y + (dx / length) * COAST_SEED_OFFSET_M,
        )
        if domain.covers(seed):
            seeds.append(seed)
    return seeds


def solve_coastline_land(admin_polygons: list[Polygon], coastlines: list[LineString]):
    """Resolve land faces using OSM's coastline direction (land is on the left).

    The administrative polygon closes the finite build domain at land borders
    and territorial limits. Which side is land is determined solely by the
    directed coastline source facts.
    """
    if not admin_polygons:
        return Polygon()
    domain = unary_union(admin_polygons)
    if not domain.is_valid:
        domain = make_valid(domain)
    if domain.is_empty:
        raise ValueError("background admin clipping domain is empty")
    if not coastlines:
        raise ValueError("background land mask requires OSM natural=coastline facts")

    linework = [domain.boundary]
    seeds: list[Point] = []
    for coastline in coastlines:
        if coastline.is_empty or len(coastline.coords) < 2:
            continue
        clipped = coastline.intersection(domain)
        if clipped.is_empty:
            continue
        if clipped.geom_type == "LineString":
            linework.append(clipped)
        elif hasattr(clipped, "geoms"):
            linework.extend(part for part in clipped.geoms if part.geom_type == "LineString" and not part.is_empty)
        seeds.extend(_left_seed_points(coastline, domain))

    faces = [face for face in polygonize(unary_union(linework)) if domain.covers(face.representative_point())]
    if not faces:
        raise ValueError("coastline linework did not partition the Sweden admin clipping domain")
    if not seeds:
        raise ValueError("coastline source produced no land-side seed points inside Sweden domain")

    tree = STRtree(faces)
    land_indexes: set[int] = set()
    for seed in seeds:
        for index in tree.query(seed, predicate="within"):
            land_indexes.add(int(index))
    if not land_indexes:
        raise ValueError("coastline solver could not identify a land-side face")
    land = unary_union([faces[index] for index in sorted(land_indexes)]).intersection(domain)
    if land.is_empty:
        raise ValueError("coastline solver produced an empty land mask")
    return land


class BackgroundAccumulator:
    def __init__(self) -> None:
        self.payload = bytearray()
        self.triangles = 0
        self.counts = [0, 0, 0, 0, 0]
        self.rejected_water_like = 0
        self.rejected_invalid_water = 0
        self.rejected_coastal_water = 0
        self.min_x = math.inf
        self.min_y = math.inf
        self.max_x = -math.inf
        self.max_y = -math.inf

    def add_geometry(self, kind: int, geometry) -> None:
        if geometry.is_empty:
            return
        geometry = geometry.simplify(background_spacing(kind), preserve_topology=True)
        if geometry.is_empty:
            return
        for part in iter_polygons(geometry):
            if part.is_empty or part.area <= 0.0:
                continue
            min_x, min_y, max_x, max_y = part.bounds
            if (max_x - min_x) * (max_y - min_y) < background_min_bbox_area(kind):
                continue
            written_for_area = 0
            for triangle in constrained_delaunay_triangles(part).geoms:
                if triangle.is_empty or triangle.geom_type != "Polygon" or not part.covers(triangle):
                    continue
                coords = list(triangle.exterior.coords)
                if len(coords) < 4:
                    continue
                (x1, y1), (x2, y2), (x3, y3) = coords[:3]
                self.payload.extend(BACKGROUND_TRIANGLE.pack(kind, x1, y1, x2, y2, x3, y3))
                self.triangles += 1
                written_for_area += 1
                for x, y in ((x1, y1), (x2, y2), (x3, y3)):
                    self.min_x = min(self.min_x, x)
                    self.min_y = min(self.min_y, y)
                    self.max_x = max(self.max_x, x)
                    self.max_y = max(self.max_y, y)
            if written_for_area > 0:
                self.counts[kind] += 1

    def add(self, tags, polygons: list[dict]) -> None:
        kind = background_class(tags)
        if kind is None:
            natural = _tag_get(tags, "natural")
            if natural in {"bay", "strait"}:
                self.rejected_coastal_water += 1
            if (
                _tag_get(tags, "waterway") == "riverbank"
                or _tag_get(tags, "landuse") == "basin"
                or (_tag_get(tags, "water") is not None and natural != "water")
            ):
                self.rejected_water_like += 1
            return
        for polygon in _raw_polygons(polygons):
            if kind == WATER and not polygon.is_valid:
                self.rejected_invalid_water += 1
                continue
            self.add_geometry(kind, polygon)


class BackgroundHandler(osmium.SimpleHandler):
    def __init__(self, accumulator: BackgroundAccumulator) -> None:
        super().__init__()
        self.accumulator = accumulator
        self.admin_polygons: list[Polygon] = []
        self.coastlines: list[LineString] = []

    def way(self, way: osmium.osm.Way) -> None:
        if way.tags.get("natural") != "coastline":
            return
        try:
            points = way_points(way.nodes)
        except osmium.InvalidLocationError:
            return
        if len(points) >= 2:
            self.coastlines.append(LineString(points))

    def area(self, area: osmium.osm.Area) -> None:
        polygons: list[dict] = []
        for outer in area.outer_rings():
            try:
                shell = ring_points(outer)
                holes = [ring_points(inner) for inner in area.inner_rings(outer)]
            except osmium.InvalidLocationError:
                continue
            if len(shell) >= 3:
                polygons.append({"outer": shell, "holes": [hole for hole in holes if len(hole) >= 3]})
        if is_admin_domain(area.tags):
            self.admin_polygons.extend(_raw_polygons(polygons))
        else:
            self.accumulator.add(area.tags, polygons)


def _consume_source(source: Path, accumulator: BackgroundAccumulator) -> tuple[int, int]:
    admin_polygons: list[Polygon] = []
    coastlines: list[LineString] = []
    if area_source_cache_valid(source):
        print(f"[background] shared-area-cache={source}", flush=True)
        for index, record in enumerate(iter_area_facts(source), 1):
            if record.get("geometry_type") == "coastline":
                points = [tuple(point) for point in record["geometry"]]
                if len(points) >= 2:
                    coastlines.append(LineString(points))
            elif is_admin_domain(record["tags"]):
                admin_polygons.extend(_raw_polygons(record["geometry"]))
            else:
                accumulator.add(record["tags"], record["geometry"])
            if index % 250_000 == 0:
                print(
                    f"[background] area-facts={index:,} coastlines={len(coastlines):,} "
                    f"triangles={accumulator.triangles:,}",
                    flush=True,
                )
    else:
        ensure_pbf(source)
        handler = BackgroundHandler(accumulator)
        handler.apply_file(str(source), locations=True)
        admin_polygons = handler.admin_polygons
        coastlines = handler.coastlines

    if admin_polygons:
        land = solve_coastline_land(admin_polygons, coastlines)
        accumulator.add_geometry(LAND, land)
    return len(admin_polygons), len(coastlines)


def build_background(source: Path, output: Path) -> dict:
    started = time.monotonic()
    accumulator = BackgroundAccumulator()
    print(f"[background] START source={source}", flush=True)
    admin_count, coastline_count = _consume_source(source, accumulator)

    output.mkdir(parents=True, exist_ok=True)
    temp = output / "background.brmap.tmp"
    with temp.open("wb") as handle:
        handle.write(BACKGROUND_HEADER.pack(b"BRM2", accumulator.triangles))
        handle.write(accumulator.payload)
    temp.replace(output / "background.brmap")

    manifest_path = output / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.is_file() else {}
    if "bounds" not in manifest and accumulator.triangles > 0:
        manifest["bounds"] = [accumulator.min_x, accumulator.min_y, accumulator.max_x, accumulator.max_y]
        manifest["origin_x"] = (accumulator.min_x + accumulator.max_x) * 0.5
        manifest["origin_y"] = (accumulator.min_y + accumulator.max_y) * 0.5
        manifest["tile_size"] = TILE_SIZE
    manifest["background_format"] = "BRM2"
    manifest["background"] = {
        "triangles": accumulator.triangles,
        "land_mask_source": "osm_natural_coastline",
        "admin_clip_areas": admin_count,
        "coastline_ways": coastline_count,
        "areas": {
            "land": accumulator.counts[LAND], "farmland": accumulator.counts[FARMLAND],
            "forest": accumulator.counts[FOREST], "urban": accumulator.counts[URBAN],
            "water": accumulator.counts[WATER],
        },
        "rejected_water_like": accumulator.rejected_water_like,
        "rejected_invalid_water": accumulator.rejected_invalid_water,
        "rejected_coastal_water": accumulator.rejected_coastal_water,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    elapsed = time.monotonic() - started
    print(
        f"[background] DONE triangles={accumulator.triangles:,} land-source=osm-coastline "
        f"coastlines={coastline_count:,} bytes={(output / 'background.brmap').stat().st_size:,} "
        f"elapsed={elapsed:.1f}s",
        flush=True,
    )
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--output", type=Path, default=Path("world_data"))
    args = parser.parse_args()
    build_background(args.source, args.output)


if __name__ == "__main__":
    main()
