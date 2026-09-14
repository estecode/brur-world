#!/usr/bin/env python3
"""Build deterministic connected road-surface geometry from derived OSM centerlines.

Dependencies:
- Shapely performs offline buffering, same-level union/difference, clipping, and triangulation.
- Consumes projected road polylines plus presentation class/grade metadata only; routing truth stays elsewhere.
"""

from __future__ import annotations

from dataclasses import dataclass
import math
import struct
from collections import defaultdict
from pathlib import Path
from typing import Iterable

from shapely import constrained_delaunay_triangles, union_all
from shapely.geometry import GeometryCollection, LineString, MultiPolygon, Polygon, box

BRS_HEADER = struct.Struct("<4sI")
BRS_TRIANGLE = struct.Struct("<Bbffffff")
BRS_MAGIC = b"BRS1"
SEAM_QUANTUM_M = 0.001
MITER_LIMIT = 3.0
GRADE_RENDER_STEP_M = 0.25

ROAD_WIDTHS_M = (24.0, 18.0, 12.0, 9.0, 7.0, 5.5, 4.0)


@dataclass(frozen=True)
class SurfaceWay:
    points: tuple[tuple[float, float], ...]
    road_class: int
    grade: int = 0


def road_width_m(road_class: int) -> float:
    index = max(0, min(int(road_class), len(ROAD_WIDTHS_M) - 1))
    return ROAD_WIDTHS_M[index]


def grade_from_tags(tags) -> int:
    """Collapse OSM layer/bridge/tunnel semantics to a stable signed render grade."""
    try:
        layer = int(tags.get("layer", "0"))
    except (TypeError, ValueError):
        layer = 0
    layer = max(-20, min(20, layer))
    bridge = str(tags.get("bridge", "")).lower() not in ("", "no", "false", "0")
    tunnel = str(tags.get("tunnel", "")).lower() not in ("", "no", "false", "0")
    if layer == 0 and bridge:
        layer = 1
    if layer == 0 and tunnel:
        layer = -1
    return layer


def _iter_polygons(geometry) -> Iterable[Polygon]:
    if geometry is None or geometry.is_empty:
        return
    if isinstance(geometry, Polygon):
        yield geometry
        return
    if isinstance(geometry, MultiPolygon):
        yield from geometry.geoms
        return
    if isinstance(geometry, GeometryCollection):
        for child in geometry.geoms:
            yield from _iter_polygons(child)


def _snap(value: float) -> float:
    return round(float(value) / SEAM_QUANTUM_M) * SEAM_QUANTUM_M


def _triangle_area2(points: tuple[tuple[float, float], ...]) -> float:
    (ax, ay), (bx, by), (cx, cy) = points
    return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)


def triangulate_surface(geometry) -> list[tuple[tuple[float, float], tuple[float, float], tuple[float, float]]]:
    triangles: list[tuple[tuple[float, float], tuple[float, float], tuple[float, float]]] = []
    for polygon in _iter_polygons(geometry):
        if polygon.area <= 1.0e-8:
            continue
        tri_collection = constrained_delaunay_triangles(polygon)
        for triangle in getattr(tri_collection, "geoms", (tri_collection,)):
            if not isinstance(triangle, Polygon) or triangle.area <= 1.0e-8:
                continue
            coords = list(triangle.exterior.coords)
            if len(coords) < 4:
                continue
            raw = tuple((_snap(x), _snap(y)) for x, y in coords[:3])
            if abs(_triangle_area2(raw)) <= 1.0e-8:
                continue
            if _triangle_area2(raw) < 0.0:
                raw = (raw[0], raw[2], raw[1])
            triangles.append(raw)
    triangles.sort(key=lambda tri: tuple(value for point in tri for value in point))
    return triangles


class RoadSurfaceAccumulator:
    """Collect tile-clipped road buffers and resolve same-grade ownership deterministically."""

    def __init__(self, tile_size: float) -> None:
        self.tile_size = float(tile_size)
        self._pieces: dict[tuple[int, int], dict[int, dict[int, list[Polygon]]]] = defaultdict(
            lambda: defaultdict(lambda: defaultdict(list))
        )

    def add_way(self, way: SurfaceWay) -> None:
        if len(way.points) < 2:
            return
        line = LineString(way.points)
        if line.length <= 1.0e-6:
            return
        # OSM commonly splits one physical road into multiple ways at tag changes and
        # junctions. Square caps deliberately overlap by half a road width at those
        # artificial way boundaries; the same-grade union below removes the overlap
        # and heals the triangular wedges left by flat caps. At genuine dead ends the
        # same geometry is simply a deterministic square end cap.
        surface = line.buffer(
            road_width_m(way.road_class) * 0.5,
            cap_style="square",
            join_style="mitre",
            mitre_limit=MITER_LIMIT,
        )
        if surface.is_empty:
            return
        min_x, min_y, max_x, max_y = surface.bounds
        min_tx = math.floor(min_x / self.tile_size)
        max_tx = math.floor(max_x / self.tile_size)
        min_ty = math.floor(min_y / self.tile_size)
        max_ty = math.floor(max_y / self.tile_size)
        for ty in range(min_ty, max_ty + 1):
            for tx in range(min_tx, max_tx + 1):
                tile_bounds = box(
                    tx * self.tile_size,
                    ty * self.tile_size,
                    (tx + 1) * self.tile_size,
                    (ty + 1) * self.tile_size,
                )
                clipped = surface.intersection(tile_bounds)
                for polygon in _iter_polygons(clipped):
                    if polygon.area > 1.0e-8:
                        self._pieces[(tx, ty)][int(way.grade)][int(way.road_class)].append(polygon)

    def resolve_tile(self, tile: tuple[int, int]) -> list[tuple[int, int, object]]:
        """Return class-owned geometries; lower class number wins overlap within each grade."""
        result: list[tuple[int, int, object]] = []
        grades = self._pieces.get(tile, {})
        for grade in sorted(grades):
            occupied = None
            for road_class in sorted(grades[grade]):
                pieces = grades[grade][road_class]
                merged = union_all(pieces, grid_size=SEAM_QUANTUM_M)
                if merged.is_empty:
                    continue
                owned = merged if occupied is None else merged.difference(occupied, grid_size=SEAM_QUANTUM_M)
                if not owned.is_empty:
                    result.append((road_class, grade, owned))
                occupied = merged if occupied is None else union_all(
                    [occupied, merged], grid_size=SEAM_QUANTUM_M
                )
        return result

    def triangles_for_tile(self, tile: tuple[int, int]) -> list[tuple[int, int, tuple]]:
        tx, ty = tile
        origin_x = tx * self.tile_size
        origin_y = ty * self.tile_size
        records: list[tuple[int, int, tuple]] = []
        for road_class, grade, geometry in self.resolve_tile(tile):
            for triangle in triangulate_surface(geometry):
                local = tuple((_snap(x - origin_x), _snap(y - origin_y)) for x, y in triangle)
                records.append((road_class, grade, local))
        records.sort(key=lambda item: (item[1], item[0], tuple(v for p in item[2] for v in p)))
        return records

    def tile_keys(self) -> list[tuple[int, int]]:
        return sorted(self._pieces)

    def write(self, output_dir: Path) -> dict[str, int]:
        output_dir.mkdir(parents=True, exist_ok=True)
        triangles = 0
        payload_bytes = 0
        for tx, ty in self.tile_keys():
            records = self.triangles_for_tile((tx, ty))
            if not records:
                continue
            path = output_dir / f"{tx}_{ty}.brmesh"
            with path.open("wb") as file:
                file.write(BRS_HEADER.pack(BRS_MAGIC, len(records)))
                for road_class, grade, triangle in records:
                    (x1, y1), (x2, y2), (x3, y3) = triangle
                    file.write(BRS_TRIANGLE.pack(road_class, grade, x1, y1, x2, y2, x3, y3))
            triangles += len(records)
            payload_bytes += path.stat().st_size
        return {"tiles": len(self.tile_keys()), "triangles": triangles, "bytes": payload_bytes}


def duplicate_triangle_area(records: list[tuple[int, int, tuple]]) -> float:
    """Test helper: duplicate coplanar triangle area after deterministic ownership resolution."""
    seen: set[tuple[int, tuple]] = set()
    duplicate = 0.0
    for _road_class, grade, triangle in records:
        key = (grade, tuple(sorted(triangle)))
        area = abs(_triangle_area2(triangle)) * 0.5
        if key in seen:
            duplicate += area
        seen.add(key)
    return duplicate
