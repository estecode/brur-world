#!/usr/bin/env python3
"""Build the BRM2 triangulated OSM background map from an OSM PBF source."""

from __future__ import annotations

import argparse
import json
import math
import struct
from pathlib import Path

import osmium
from shapely import constrained_delaunay_triangles, make_valid
from shapely.geometry import Polygon

from world_common import TILE_SIZE, ensure_pbf, project

BACKGROUND_HEADER = struct.Struct("<4sI")
BACKGROUND_TRIANGLE = struct.Struct("<Bffffff")

LAND = 0
FARMLAND = 1
FOREST = 2
URBAN = 3
WATER = 4

# Only tags that actually describe a water surface. In particular, do not use
# the mere presence of water=* as a water test: OSM objects can carry auxiliary
# water tags without natural=water, and bad/incomplete relations can otherwise
# paint enormous areas blue.
WATER_NATURAL = {"water", "bay", "strait"}
WATER_LANDUSE = {"reservoir"}


def background_class(tags: osmium.osm.TagList) -> int | None:
    # The runtime uses a water base plane. Country boundaries paint land back on
    # top, so explicit WATER polygons are only inland/explicit water surfaces.
    if tags.get("boundary") == "administrative" and tags.get("admin_level") == "2":
        return LAND

    natural = tags.get("natural")
    landuse = tags.get("landuse")

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


def iter_polygons(geometry):
    if geometry.is_empty:
        return
    if geometry.geom_type == "Polygon":
        yield geometry
        return
    if hasattr(geometry, "geoms"):
        for child in geometry.geoms:
            yield from iter_polygons(child)


class BackgroundHandler(osmium.SimpleHandler):
    def __init__(self) -> None:
        super().__init__()
        self.payload = bytearray()
        self.triangles = 0
        self.counts = [0, 0, 0, 0, 0]
        self.rejected_water_like = 0
        self.rejected_invalid_water = 0
        self.min_x = math.inf
        self.min_y = math.inf
        self.max_x = -math.inf
        self.max_y = -math.inf

    def area(self, area: osmium.osm.Area) -> None:
        kind = background_class(area.tags)
        if kind is None:
            if (
                area.tags.get("waterway") == "riverbank"
                or area.tags.get("landuse") == "basin"
                or (area.tags.get("water") is not None and area.tags.get("natural") != "water")
            ):
                self.rejected_water_like += 1
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

            # Invalid water polygons are dangerous for a map mask: make_valid()
            # can turn a broken relation into large disconnected pieces. Reject
            # them instead. Other background classes keep the repair behavior.
            if kind == WATER and not polygon.is_valid:
                self.rejected_invalid_water += 1
                continue

            geometry = polygon if polygon.is_valid else make_valid(polygon)
            geometry = geometry.simplify(background_spacing(kind), preserve_topology=True)
            if geometry.is_empty:
                continue

            written_for_area = 0
            for part in iter_polygons(geometry):
                if part.is_empty or part.area <= 0.0:
                    continue
                for triangle in constrained_delaunay_triangles(part).geoms:
                    if triangle.is_empty or triangle.geom_type != "Polygon":
                        continue
                    if not part.covers(triangle):
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


def build_background(pbf: Path, output: Path) -> dict:
    ensure_pbf(pbf)
    handler = BackgroundHandler()
    print(f"[background] Reading {pbf} ...", flush=True)
    handler.apply_file(str(pbf), locations=True)

    output.mkdir(parents=True, exist_ok=True)
    with (output / "background.brmap").open("wb") as f:
        f.write(BACKGROUND_HEADER.pack(b"BRM2", handler.triangles))
        f.write(handler.payload)

    manifest_path = output / "manifest.json"
    manifest = {}
    if manifest_path.is_file():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    if "bounds" not in manifest and handler.triangles > 0:
        manifest["bounds"] = [handler.min_x, handler.min_y, handler.max_x, handler.max_y]
        manifest["origin_x"] = (handler.min_x + handler.max_x) * 0.5
        manifest["origin_y"] = (handler.min_y + handler.max_y) * 0.5
        manifest["tile_size"] = TILE_SIZE

    manifest["background_format"] = "BRM2"
    manifest["background"] = {
        "triangles": handler.triangles,
        "areas": {
            "land": handler.counts[LAND],
            "farmland": handler.counts[FARMLAND],
            "forest": handler.counts[FOREST],
            "urban": handler.counts[URBAN],
            "water": handler.counts[WATER],
        },
        "rejected_water_like": handler.rejected_water_like,
        "rejected_invalid_water": handler.rejected_invalid_water,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    print(
        "[background] Areas: "
        f"land={handler.counts[LAND]:,}, "
        f"farmland={handler.counts[FARMLAND]:,}, "
        f"forest={handler.counts[FOREST]:,}, "
        f"urban={handler.counts[URBAN]:,}, "
        f"water={handler.counts[WATER]:,}"
    )
    print(f"[background] Rejected ambiguous water-like areas: {handler.rejected_water_like:,}")
    print(f"[background] Rejected invalid water polygons: {handler.rejected_invalid_water:,}")
    print(f"[background] Triangles: {handler.triangles:,}")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pbf", type=Path)
    parser.add_argument("--output", type=Path, default=Path("world_data"))
    args = parser.parse_args()
    build_background(args.pbf, args.output)


if __name__ == "__main__":
    main()
