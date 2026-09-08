"""Build and query a compact persistent road-snap index for BRG1 routing.

Dependencies:
- routing_graph.py / routing_graph_view.py provide BRG1 graph records.
- gps_routing.py owns RoadSnap and DirectedSnap result data.
- This module keeps expensive Sweden-wide spatial indexing offline.
"""

from __future__ import annotations

import math
import mmap
import struct
import time
from collections import defaultdict
from pathlib import Path
from typing import Iterable

from gps_routing import DirectedSnap, RoadSnap
from routing_graph import RoutingProfile, is_edge_allowed


MAGIC = b"BRS2"
HEADER = struct.Struct("<4sfIIf")
CELL = struct.Struct("<iiII")
EDGE_REF = struct.Struct("<I")
DEFAULT_CELL_SIZE_M = 256.0
PROGRESS_SECONDS = 5.0


def _closest_point(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> tuple[float, float, float]:
    dx = bx - ax
    dy = by - ay
    length_sq = dx * dx + dy * dy
    if length_sq <= 0.0:
        return ax, ay, 0.0
    fraction = ((px - ax) * dx + (py - ay) * dy) / length_sq
    fraction = max(0.0, min(1.0, fraction))
    return ax + dx * fraction, ay + dy * fraction, fraction


def _cell_bounds(graph, edge_index: int, cell_size_m: float) -> tuple[int, int, int, int]:
    edge = graph.edges[edge_index]
    a = graph.nodes[edge.source_index]
    b = graph.nodes[edge.target_index]
    return (
        math.floor(min(a.x, b.x) / cell_size_m),
        math.floor(min(a.y, b.y) / cell_size_m),
        math.floor(max(a.x, b.x) / cell_size_m),
        math.floor(max(a.y, b.y) / cell_size_m),
    )


def build_snap_index(graph, path: Path, cell_size_m: float = DEFAULT_CELL_SIZE_M) -> dict[str, int | float]:
    """Build BRS2 once offline; one representative is stored per physical edge.

    The file also stores the maximum legal NORMAL-profile edge speed. The router
    uses that value as a mathematically admissible A* time heuristic bound.
    """
    if cell_size_m <= 0.0:
        raise ValueError("cell_size_m must be positive")
    started = time.perf_counter()
    last_print = started
    cells: dict[tuple[int, int], list[int]] = defaultdict(list)
    physical_edges = 0
    max_legal_speed_kmh = 0.0

    edge_total = len(graph.edges)
    for edge_index in range(edge_total):
        edge = graph.edges[edge_index]
        if is_edge_allowed(edge, RoutingProfile.NORMAL):
            max_legal_speed_kmh = max(max_legal_speed_kmh, float(edge.speed_kmh))

        if edge.source_index >= edge.target_index:
            continue
        physical_edges += 1
        min_cx, min_cy, max_cx, max_cy = _cell_bounds(graph, edge_index, cell_size_m)
        for cx in range(min_cx, max_cx + 1):
            for cy in range(min_cy, max_cy + 1):
                cells[(cx, cy)].append(edge_index)
        now = time.perf_counter()
        if now - last_print >= PROGRESS_SECONDS:
            elapsed = now - started
            print(
                f"[snap-index] scanning edges: {edge_index + 1:,}/{edge_total:,} | "
                f"{physical_edges:,} physical | {len(cells):,} cells | "
                f"max legal {max_legal_speed_kmh:.1f} km/h | {elapsed:.1f}s",
                flush=True,
            )
            last_print = now

    if max_legal_speed_kmh <= 0.0:
        raise ValueError("routing graph has no NORMAL-profile legal edge speed")

    ordered_cells = sorted(cells.items())
    ref_count = sum(len(refs) for _, refs in ordered_cells)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    try:
        with temp.open("wb") as handle:
            handle.write(
                HEADER.pack(
                    MAGIC,
                    float(cell_size_m),
                    len(ordered_cells),
                    ref_count,
                    float(max_legal_speed_kmh),
                )
            )
            offset = 0
            for (cx, cy), refs in ordered_cells:
                refs.sort()
                handle.write(CELL.pack(cx, cy, offset, len(refs)))
                offset += len(refs)
            for _, refs in ordered_cells:
                for edge_index in refs:
                    handle.write(EDGE_REF.pack(edge_index))
        temp.replace(path)
    except BaseException:
        if temp.exists():
            temp.unlink()
        raise

    elapsed = time.perf_counter() - started
    print(
        f"[snap-index] done: {physical_edges:,} physical edges, {len(ordered_cells):,} cells, "
        f"{ref_count:,} refs, max legal {max_legal_speed_kmh:.1f} km/h, "
        f"{path.stat().st_size:,} bytes, {elapsed:.1f}s",
        flush=True,
    )
    return {
        "physical_edge_count": physical_edges,
        "cell_count": len(ordered_cells),
        "reference_count": ref_count,
        "max_legal_speed_kmh": max_legal_speed_kmh,
        "output_bytes": path.stat().st_size,
        "build_seconds": round(elapsed, 3),
    }


class PersistentRoadSnapIndex:
    """Memory-map BRS2 and query nearby physical edges without a startup rebuild."""

    def __init__(self, graph, path: Path, profile: RoutingProfile = RoutingProfile.NORMAL) -> None:
        self.graph = graph
        self.profile = profile
        self.path = Path(path)
        self._file = self.path.open("rb")
        try:
            self._map = mmap.mmap(self._file.fileno(), 0, access=mmap.ACCESS_READ)
            if len(self._map) < HEADER.size:
                raise ValueError("BRS2 header is truncated")
            (
                magic,
                self.cell_size_m,
                self.cell_count,
                self.ref_count,
                self.max_legal_speed_kmh,
            ) = HEADER.unpack_from(self._map, 0)
            if magic != MAGIC:
                raise ValueError(f"Unsupported snap index magic: {magic!r}; rebuild routing_snap.brs")
            if self.max_legal_speed_kmh <= 0.0:
                raise ValueError("BRS2 has invalid legal speed bound")
            self._cell_table_offset = HEADER.size
            self._ref_table_offset = self._cell_table_offset + self.cell_count * CELL.size
            expected = self._ref_table_offset + self.ref_count * EDGE_REF.size
            if len(self._map) != expected:
                raise ValueError(f"BRS2 file size mismatch: expected {expected}, got {len(self._map)}")
        except Exception:
            if getattr(self, "_map", None) is not None:
                self._map.close()
                self._map = None
            self._file.close()
            raise

    def close(self) -> None:
        if getattr(self, "_map", None) is not None:
            self._map.close()
            self._map = None
        if getattr(self, "_file", None) is not None:
            self._file.close()
            self._file = None

    def __enter__(self) -> "PersistentRoadSnapIndex":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def _cell_record(self, index: int) -> tuple[int, int, int, int]:
        return CELL.unpack_from(self._map, self._cell_table_offset + index * CELL.size)

    def _refs_for_cell(self, cx: int, cy: int) -> Iterable[int]:
        wanted = (cx, cy)
        low = 0
        high = self.cell_count
        while low < high:
            middle = (low + high) // 2
            cell = self._cell_record(middle)
            key = (cell[0], cell[1])
            if key < wanted:
                low = middle + 1
            else:
                high = middle
        if low >= self.cell_count:
            return ()
        cell = self._cell_record(low)
        if (cell[0], cell[1]) != wanted:
            return ()
        offset, count = cell[2], cell[3]
        return (
            EDGE_REF.unpack_from(self._map, self._ref_table_offset + (offset + item) * EDGE_REF.size)[0]
            for item in range(count)
        )

    def _directions(self, representative_index: int, fraction: float) -> tuple[DirectedSnap, ...]:
        representative = self.graph.edges[representative_index]
        found: list[DirectedSnap] = []
        if is_edge_allowed(representative, self.profile):
            found.append(DirectedSnap(representative_index, fraction))

        target = self.graph.nodes[representative.target_index]
        start = target.adjacency_offset
        end = start + target.adjacency_count
        for edge_index in range(start, end):
            edge = self.graph.edges[edge_index]
            if (
                edge.target_index == representative.source_index
                and edge.way_id == representative.way_id
                and edge.segment_index == representative.segment_index
            ):
                if is_edge_allowed(edge, self.profile):
                    found.append(DirectedSnap(edge_index, 1.0 - fraction))
                break
        found.sort(key=lambda item: item.edge_index)
        return tuple(found)

    def snap_with_stats(self, x: float, y: float, max_distance_m: float = 250.0) -> tuple[RoadSnap | None, int]:
        """Snap and report how many unique segment candidates were tested."""
        if max_distance_m < 0.0:
            raise ValueError("max_distance_m must be non-negative")
        cx = math.floor(x / self.cell_size_m)
        cy = math.floor(y / self.cell_size_m)
        radius = int(math.ceil(max_distance_m / self.cell_size_m)) + 1
        candidates: set[int] = set()
        for ix in range(cx - radius, cx + radius + 1):
            for iy in range(cy - radius, cy + radius + 1):
                candidates.update(self._refs_for_cell(ix, iy))

        best: tuple[float, int, float, float, float] | None = None
        for edge_index in sorted(candidates):
            edge = self.graph.edges[edge_index]
            a = self.graph.nodes[edge.source_index]
            b = self.graph.nodes[edge.target_index]
            px, py, fraction = _closest_point(x, y, a.x, a.y, b.x, b.y)
            distance = math.hypot(x - px, y - py)
            candidate = (distance, edge_index, fraction, px, py)
            if best is None or candidate[:2] < best[:2]:
                best = candidate

        if best is None or best[0] > max_distance_m:
            return None, len(candidates)
        distance, edge_index, fraction, px, py = best
        return RoadSnap(px, py, distance, self._directions(edge_index, fraction)), len(candidates)

    def snap(self, x: float, y: float, max_distance_m: float = 250.0) -> RoadSnap | None:
        snap, _ = self.snap_with_stats(x, y, max_distance_m)
        return snap
