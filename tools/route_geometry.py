"""Read and validate compact per-edge route geometry sidecars.

Dependencies:
- Pure Python and the standard library only.
- The offline routing compiler writes BRH1; tests and tooling may read it.
- Runtime C++ has an equivalent read-only view in native/gps_route_geometry.h.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path


MAGIC = b"BRH1"
HEADER = struct.Struct("<4sII")
EDGE_RECORD = struct.Struct("<IIB3x")
POINT_RECORD = struct.Struct("<ff")


@dataclass(frozen=True)
class RouteGeometryEntry:
    point_offset: int
    point_count: int
    reversed: bool


class RouteGeometryView:
    """Small in-memory reader used by deterministic tests and offline validation."""

    def __init__(self, data: bytes) -> None:
        if len(data) < HEADER.size:
            raise ValueError("BRH1 header is truncated")
        magic, self.edge_count, self.point_count = HEADER.unpack_from(data, 0)
        if magic != MAGIC:
            raise ValueError(f"Unsupported route geometry magic: {magic!r}")
        self._data = data
        self._point_table_offset = HEADER.size + self.edge_count * EDGE_RECORD.size
        expected = self._point_table_offset + self.point_count * POINT_RECORD.size
        if len(data) != expected:
            raise ValueError(f"BRH1 file size mismatch: expected {expected}, got {len(data)}")

    @classmethod
    def load(cls, path: Path) -> "RouteGeometryView":
        return cls(Path(path).read_bytes())

    def entry(self, edge_index: int) -> RouteGeometryEntry:
        if not 0 <= edge_index < self.edge_count:
            raise IndexError(edge_index)
        offset = HEADER.size + edge_index * EDGE_RECORD.size
        point_offset, point_count, reversed_flag = EDGE_RECORD.unpack_from(self._data, offset)
        if point_offset + point_count > self.point_count:
            raise ValueError("BRH1 edge geometry points are out of range")
        return RouteGeometryEntry(point_offset, point_count, bool(reversed_flag))

    def edge_points(self, edge_index: int) -> tuple[tuple[float, float], ...]:
        entry = self.entry(edge_index)
        points: list[tuple[float, float]] = []
        for point_index in range(entry.point_offset, entry.point_offset + entry.point_count):
            offset = self._point_table_offset + point_index * POINT_RECORD.size
            points.append(POINT_RECORD.unpack_from(self._data, offset))
        if entry.reversed:
            points.reverse()
        return tuple(points)


def validate_route_geometry(path: Path, edge_count: int) -> RouteGeometryView:
    view = RouteGeometryView.load(path)
    if view.edge_count != edge_count:
        raise ValueError(f"BRH1 edge count mismatch: expected {edge_count}, got {view.edge_count}")
    return view
