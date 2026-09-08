"""Read BRG1 lazily through mmap without expanding the Sweden graph into Python objects.

Dependencies:
- routing_graph.py owns the BRG1 record definitions and graph dataclasses.
- gps_routing.py can use this view through the same nodes/edges indexing interface.
"""

from __future__ import annotations

import mmap
from pathlib import Path
from typing import Iterator, Sequence, overload

from routing_graph import (
    AccessClass,
    AccessReason,
    EDGE_RECORD,
    GraphEdge,
    GraphNode,
    HEADER,
    MAGIC,
    NODE_RECORD,
    SpeedSource,
)


class _NodeView(Sequence[GraphNode]):
    def __init__(self, owner: "RoutingGraphView") -> None:
        self._owner = owner

    def __len__(self) -> int:
        return self._owner.node_count

    @overload
    def __getitem__(self, index: int) -> GraphNode: ...
    @overload
    def __getitem__(self, index: slice) -> tuple[GraphNode, ...]: ...

    def __getitem__(self, index: int | slice) -> GraphNode | tuple[GraphNode, ...]:
        if isinstance(index, slice):
            return tuple(self[i] for i in range(*index.indices(len(self))))
        if index < 0:
            index += len(self)
        if not 0 <= index < len(self):
            raise IndexError(index)
        offset = HEADER.size + index * NODE_RECORD.size
        osm_id, lon, lat, x, y, adjacency_offset, adjacency_count = NODE_RECORD.unpack_from(self._owner._map, offset)
        return GraphNode(osm_id, lon, lat, x, y, adjacency_offset, adjacency_count)

    def __iter__(self) -> Iterator[GraphNode]:
        for index in range(len(self)):
            yield self[index]


class _EdgeView(Sequence[GraphEdge]):
    def __init__(self, owner: "RoutingGraphView") -> None:
        self._owner = owner

    def __len__(self) -> int:
        return self._owner.edge_count

    @overload
    def __getitem__(self, index: int) -> GraphEdge: ...
    @overload
    def __getitem__(self, index: slice) -> tuple[GraphEdge, ...]: ...

    def __getitem__(self, index: int | slice) -> GraphEdge | tuple[GraphEdge, ...]:
        if isinstance(index, slice):
            return tuple(self[i] for i in range(*index.indices(len(self))))
        if index < 0:
            index += len(self)
        if not 0 <= index < len(self):
            raise IndexError(index)
        offset = self._owner._edge_table_offset + index * EDGE_RECORD.size
        values = EDGE_RECORD.unpack_from(self._owner._map, offset)
        return GraphEdge(
            values[0], values[1], values[2], values[3], values[4], values[5], values[6],
            AccessClass(values[7]), values[8], SpeedSource(values[9]), values[10], AccessReason(values[11]),
        )

    def __iter__(self) -> Iterator[GraphEdge]:
        for index in range(len(self)):
            yield self[index]


class RoutingGraphView:
    """Read-only BRG1 view with constant-size process-side graph storage."""

    def __init__(self, path: Path) -> None:
        self.path = Path(path)
        self._file = self.path.open("rb")
        try:
            self._map = mmap.mmap(self._file.fileno(), 0, access=mmap.ACCESS_READ)
            if len(self._map) < HEADER.size:
                raise ValueError("BRG1 header is truncated")
            magic, self.node_count, self.edge_count = HEADER.unpack_from(self._map, 0)
            if magic != MAGIC:
                raise ValueError(f"Unsupported routing graph magic: {magic!r}")
            self._edge_table_offset = HEADER.size + self.node_count * NODE_RECORD.size
            expected = self._edge_table_offset + self.edge_count * EDGE_RECORD.size
            if len(self._map) != expected:
                raise ValueError(f"BRG1 file size mismatch: expected {expected}, got {len(self._map)}")
            self.nodes = _NodeView(self)
            self.edges = _EdgeView(self)
        except Exception:
            self._file.close()
            raise

    def close(self) -> None:
        if getattr(self, "_map", None) is not None:
            self._map.close()
            self._map = None
        if getattr(self, "_file", None) is not None:
            self._file.close()
            self._file = None

    def __enter__(self) -> "RoutingGraphView":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def stable_edge_id(self, edge: GraphEdge) -> str:
        source_osm = self.nodes[edge.source_index].osm_id
        target_osm = self.nodes[edge.target_index].osm_id
        return f"w{edge.way_id}:{source_osm}>{target_osm}:{edge.segment_index}"
