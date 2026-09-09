"""Read and validate compact per-edge route geometry sidecars.

Dependencies:
- Uses shared world projection conversion and routing graph distance semantics.
- The offline routing compiler writes BRH1; tests and tooling may read it.
- Runtime C++ has an equivalent read-only view in native/gps_route_geometry.h.
"""

from __future__ import annotations

import math
import mmap
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from world_common import unproject


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
    """Small in-memory reader used by deterministic tests."""

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


def validate_route_geometry(path: Path, edge_count: int) -> tuple[int, int]:
    """Validate a potentially huge BRH1 file using only its header and file size."""
    path = Path(path)
    with path.open("rb") as handle:
        raw_header = handle.read(HEADER.size)
    if len(raw_header) != HEADER.size:
        raise ValueError("BRH1 header is truncated")
    magic, written_edges, point_count = HEADER.unpack(raw_header)
    if magic != MAGIC:
        raise ValueError(f"Unsupported route geometry magic: {magic!r}")
    if written_edges != edge_count:
        raise ValueError(f"BRH1 edge count mismatch: expected {edge_count}, got {written_edges}")
    expected = HEADER.size + written_edges * EDGE_RECORD.size + point_count * POINT_RECORD.size
    actual = path.stat().st_size
    if actual != expected:
        raise ValueError(f"BRH1 file size mismatch: expected {expected}, got {actual}")
    return written_edges, point_count


def validate_route_geometry_alignment(
    graph_path: Path,
    geometry_path: Path,
    *,
    endpoint_tolerance_m: float = 2.0,
    length_relative_tolerance: float = 0.005,
    length_absolute_tolerance_m: float = 5.0,
    progress: Callable[[int, int], None] | None = None,
) -> dict[str, float | int]:
    """Verify every BRH1 edge is the detailed shape of the same directed BRG1 edge.

    Endpoint alignment catches edge-index/data-generation mismatches. Geometry length
    catches a compressed curved edge that accidentally collapsed back to its endpoint chord.
    Reverse records share the same stored physical shape, so length is scanned once.
    """
    from routing_graph import EDGE_RECORD as GRAPH_EDGE_RECORD
    from routing_graph import HEADER as GRAPH_HEADER
    from routing_graph import MAGIC as GRAPH_MAGIC
    from routing_graph import NODE_RECORD as GRAPH_NODE_RECORD
    from routing_graph import geodesic_distance_m

    graph_path = Path(graph_path)
    geometry_path = Path(geometry_path)
    with graph_path.open("rb") as graph_file, geometry_path.open("rb") as geometry_file:
        graph = mmap.mmap(graph_file.fileno(), 0, access=mmap.ACCESS_READ)
        geometry = mmap.mmap(geometry_file.fileno(), 0, access=mmap.ACCESS_READ)
        try:
            if len(graph) < GRAPH_HEADER.size:
                raise ValueError("BRG1 header is truncated")
            graph_magic, node_count, edge_count = GRAPH_HEADER.unpack_from(graph, 0)
            if graph_magic != GRAPH_MAGIC:
                raise ValueError(f"Unsupported routing graph magic: {graph_magic!r}")
            graph_edge_offset = GRAPH_HEADER.size + node_count * GRAPH_NODE_RECORD.size
            expected_graph_size = graph_edge_offset + edge_count * GRAPH_EDGE_RECORD.size
            if len(graph) != expected_graph_size:
                raise ValueError(
                    f"BRG1 file size mismatch: expected {expected_graph_size}, got {len(graph)}"
                )

            if len(geometry) < HEADER.size:
                raise ValueError("BRH1 header is truncated")
            geometry_magic, geometry_edges, point_count = HEADER.unpack_from(geometry, 0)
            if geometry_magic != MAGIC:
                raise ValueError(f"Unsupported route geometry magic: {geometry_magic!r}")
            if geometry_edges != edge_count:
                raise ValueError(
                    f"BRH1 edge count mismatch: expected {edge_count}, got {geometry_edges}"
                )
            point_table_offset = HEADER.size + edge_count * EDGE_RECORD.size
            expected_geometry_size = point_table_offset + point_count * POINT_RECORD.size
            if len(geometry) != expected_geometry_size:
                raise ValueError(
                    f"BRH1 file size mismatch: expected {expected_geometry_size}, got {len(geometry)}"
                )

            def node_xy(index: int) -> tuple[float, float]:
                if not 0 <= index < node_count:
                    raise ValueError(f"BRG1 node index out of range: {index}")
                offset = GRAPH_HEADER.size + index * GRAPH_NODE_RECORD.size
                values = GRAPH_NODE_RECORD.unpack_from(graph, offset)
                return float(values[3]), float(values[4])

            def stored_point(index: int) -> tuple[float, float]:
                if not 0 <= index < point_count:
                    raise ValueError(f"BRH1 point index out of range: {index}")
                offset = point_table_offset + index * POINT_RECORD.size
                x, y = POINT_RECORD.unpack_from(geometry, offset)
                return float(x), float(y)

            max_endpoint_error = 0.0
            max_length_error = 0.0
            physical_shapes_checked = 0
            for edge_index in range(edge_count):
                edge_offset = graph_edge_offset + edge_index * GRAPH_EDGE_RECORD.size
                edge = GRAPH_EDGE_RECORD.unpack_from(graph, edge_offset)
                source_index = int(edge[2])
                target_index = int(edge[3])
                edge_length_m = float(edge[4])

                entry_offset = HEADER.size + edge_index * EDGE_RECORD.size
                point_offset, point_count_for_edge, reversed_flag = EDGE_RECORD.unpack_from(
                    geometry, entry_offset
                )
                if point_count_for_edge < 2:
                    raise ValueError(f"BRH1 edge {edge_index} has fewer than two shape points")
                if point_offset + point_count_for_edge > point_count:
                    raise ValueError(f"BRH1 edge {edge_index} shape range is out of bounds")

                first_index = point_offset + (point_count_for_edge - 1 if reversed_flag else 0)
                last_index = point_offset + (0 if reversed_flag else point_count_for_edge - 1)
                first = stored_point(first_index)
                last = stored_point(last_index)
                source = node_xy(source_index)
                target = node_xy(target_index)
                source_error = math.hypot(first[0] - source[0], first[1] - source[1])
                target_error = math.hypot(last[0] - target[0], last[1] - target[1])
                max_endpoint_error = max(max_endpoint_error, source_error, target_error)
                if source_error > endpoint_tolerance_m or target_error > endpoint_tolerance_m:
                    raise ValueError(
                        f"BRG1/BRH1 edge {edge_index} endpoint mismatch: "
                        f"source={source_error:.3f}m target={target_error:.3f}m"
                    )

                if not reversed_flag:
                    previous = stored_point(point_offset)
                    previous_lonlat = unproject(*previous)
                    geometry_length_m = 0.0
                    for point_index in range(point_offset + 1, point_offset + point_count_for_edge):
                        current = stored_point(point_index)
                        current_lonlat = unproject(*current)
                        geometry_length_m += geodesic_distance_m(previous_lonlat, current_lonlat)
                        previous_lonlat = current_lonlat
                    length_error = abs(geometry_length_m - edge_length_m)
                    max_length_error = max(max_length_error, length_error)
                    tolerance = max(
                        length_absolute_tolerance_m,
                        edge_length_m * length_relative_tolerance,
                    )
                    if length_error > tolerance:
                        raise ValueError(
                            f"BRG1/BRH1 edge {edge_index} geometry length mismatch: "
                            f"graph={edge_length_m:.3f}m shape={geometry_length_m:.3f}m "
                            f"error={length_error:.3f}m tolerance={tolerance:.3f}m"
                        )
                    physical_shapes_checked += 1

                if progress is not None and ((edge_index + 1) % 250_000 == 0 or edge_index + 1 == edge_count):
                    progress(edge_index + 1, edge_count)

            return {
                "edge_count": edge_count,
                "physical_shape_count": physical_shapes_checked,
                "point_count": point_count,
                "max_endpoint_error_m": max_endpoint_error,
                "max_length_error_m": max_length_error,
            }
        finally:
            graph.close()
            geometry.close()
