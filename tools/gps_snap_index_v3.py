"""Build the fixed-point BRS3 road-segment snap sidecar.

Dependencies:
- routing_graph/routing_graph_view expose the authoritative BRG1 topology.
- This module is offline-only and writes portable little-endian snap data.
- Rendering/Web-Mercator ownership is unchanged; BRS3 stores local centimetre offsets.
"""

from __future__ import annotations

import math
import struct
import time
from collections import defaultdict
from pathlib import Path

from routing_graph import RoutingProfile, is_edge_allowed

MAGIC = b"BRS3"
VERSION = 1
HEADER = struct.Struct("<4sIIIIIddfI")
CELL = struct.Struct("<iiII")
SEGMENT = struct.Struct("<IIiiii")
REF = struct.Struct("<I")
DEFAULT_CELL_SIZE_M = 256.0
CENTIMETRES_PER_METER = 100
NO_EDGE = 0xFFFFFFFF
PROGRESS_SECONDS = 5.0


def _reverse_edge(graph, representative_index: int) -> int:
    representative = graph.edges[representative_index]
    target = graph.nodes[representative.target_index]
    for edge_index in range(target.adjacency_offset, target.adjacency_offset + target.adjacency_count):
        edge = graph.edges[edge_index]
        if (
            edge.target_index == representative.source_index
            and edge.way_id == representative.way_id
            and edge.segment_index == representative.segment_index
        ):
            return edge_index
    return NO_EDGE


def _local_cm(value: float, origin: float) -> int:
    scaled = int(round((float(value) - origin) * CENTIMETRES_PER_METER))
    if not -(1 << 31) <= scaled < (1 << 31):
        raise OverflowError("BRS3 fixed-point coordinate exceeds int32 range")
    return scaled


def build_snap_index_v3(graph, path: Path, cell_size_m: float = DEFAULT_CELL_SIZE_M) -> dict[str, int | float]:
    """Build a flat CSR grid over legal physical road segments.

    BRS3 stores local int32 centimetre endpoints plus both legal directed BRG edge
    identities, so runtime snapping needs no graph-node lookup or reverse-edge scan.
    """
    if cell_size_m <= 0.0:
        raise ValueError("cell_size_m must be positive")
    node_count = len(graph.nodes)
    if node_count == 0:
        raise ValueError("routing graph has no nodes")

    started = time.perf_counter()
    last_print = started
    min_x = math.inf
    min_y = math.inf
    for node_index in range(node_count):
        node = graph.nodes[node_index]
        min_x = min(min_x, float(node.x))
        min_y = min(min_y, float(node.y))
        now = time.perf_counter()
        if now - last_print >= PROGRESS_SECONDS:
            print(
                f"[snap-v3] origin scan: {node_index + 1:,}/{node_count:,} nodes | {now - started:.1f}s",
                flush=True,
            )
            last_print = now

    origin_x = math.floor(min_x)
    origin_y = math.floor(min_y)
    cell_size_cm = int(round(cell_size_m * CENTIMETRES_PER_METER))
    if cell_size_cm <= 0:
        raise ValueError("cell size rounds to zero centimetres")

    segments: list[tuple[int, int, int, int, int, int]] = []
    cells: dict[tuple[int, int], list[int]] = defaultdict(list)
    max_legal_speed_kmh = 0.0
    edge_total = len(graph.edges)
    last_print = time.perf_counter()
    scan_started = last_print

    for edge_index in range(edge_total):
        edge = graph.edges[edge_index]
        if edge.source_index >= edge.target_index:
            continue

        reverse_index = _reverse_edge(graph, edge_index)
        forward = edge_index if is_edge_allowed(edge, RoutingProfile.NORMAL) else NO_EDGE
        reverse = NO_EDGE
        if reverse_index != NO_EDGE:
            reverse_edge = graph.edges[reverse_index]
            if is_edge_allowed(reverse_edge, RoutingProfile.NORMAL):
                reverse = reverse_index
        if forward == NO_EDGE and reverse == NO_EDGE:
            continue

        if forward != NO_EDGE:
            max_legal_speed_kmh = max(max_legal_speed_kmh, float(edge.speed_kmh))
        if reverse != NO_EDGE:
            max_legal_speed_kmh = max(max_legal_speed_kmh, float(graph.edges[reverse].speed_kmh))

        a = graph.nodes[edge.source_index]
        b = graph.nodes[edge.target_index]
        ax = _local_cm(a.x, origin_x)
        ay = _local_cm(a.y, origin_y)
        bx = _local_cm(b.x, origin_x)
        by = _local_cm(b.y, origin_y)
        segment_index = len(segments)
        segments.append((forward, reverse, ax, ay, bx, by))

        min_cx = min(ax, bx) // cell_size_cm
        max_cx = max(ax, bx) // cell_size_cm
        min_cy = min(ay, by) // cell_size_cm
        max_cy = max(ay, by) // cell_size_cm
        for cx in range(min_cx, max_cx + 1):
            for cy in range(min_cy, max_cy + 1):
                cells[(cx, cy)].append(segment_index)

        now = time.perf_counter()
        if now - last_print >= PROGRESS_SECONDS:
            print(
                f"[snap-v3] segments: {edge_index + 1:,}/{edge_total:,} edges | "
                f"{len(segments):,} segments | {len(cells):,} cells | {now - scan_started:.1f}s",
                flush=True,
            )
            last_print = now

    if not segments or max_legal_speed_kmh <= 0.0:
        raise ValueError("routing graph has no NORMAL-profile routable physical segments")

    ordered_cells = sorted(cells.items())
    ref_count = sum(len(refs) for _, refs in ordered_cells)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    try:
        with temp.open("wb") as handle:
            handle.write(
                HEADER.pack(
                    MAGIC,
                    VERSION,
                    cell_size_cm,
                    len(ordered_cells),
                    len(segments),
                    ref_count,
                    float(origin_x),
                    float(origin_y),
                    float(max_legal_speed_kmh),
                    0,
                )
            )
            offset = 0
            for (cx, cy), refs in ordered_cells:
                refs.sort()
                handle.write(CELL.pack(cx, cy, offset, len(refs)))
                offset += len(refs)
            for segment in segments:
                handle.write(SEGMENT.pack(*segment))
            for _, refs in ordered_cells:
                for segment_index in refs:
                    handle.write(REF.pack(segment_index))
        temp.replace(path)
    except BaseException:
        if temp.exists():
            temp.unlink()
        raise

    elapsed = time.perf_counter() - started
    print(
        f"[snap-v3] done: {len(segments):,} segments, {len(ordered_cells):,} cells, "
        f"{ref_count:,} refs, {path.stat().st_size:,} bytes, {elapsed:.1f}s",
        flush=True,
    )
    return {
        "segment_count": len(segments),
        "cell_count": len(ordered_cells),
        "reference_count": ref_count,
        "max_legal_speed_kmh": max_legal_speed_kmh,
        "origin_x": origin_x,
        "origin_y": origin_y,
        "cell_size_cm": cell_size_cm,
        "output_bytes": path.stat().st_size,
        "build_seconds": round(elapsed, 3),
    }
