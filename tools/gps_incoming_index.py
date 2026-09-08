"""Build and query a compact reverse-adjacency index for BRG1 routing.

Dependencies:
- routing_graph_view.py exposes BRG1 edges without expanding Sweden into objects.
- This module is offline/runtime routing infrastructure only; it owns no GPS policy.
"""

from __future__ import annotations

import array
import mmap
import struct
import time
from pathlib import Path
from typing import Iterator


MAGIC = b"BRI1"
HEADER = struct.Struct("<4sII")
UINT32 = struct.Struct("<I")
PROGRESS_SECONDS = 5.0


def build_incoming_index(graph, path: Path) -> dict[str, int | float]:
    """Build incoming-edge adjacency once offline using compact uint32 arrays."""
    node_count = len(graph.nodes)
    edge_count = len(graph.edges)
    started = time.perf_counter()
    last_print = started

    counts = array.array("I", [0]) * node_count
    for edge_index in range(edge_count):
        edge = graph.edges[edge_index]
        counts[edge.target_index] += 1
        now = time.perf_counter()
        if now - last_print >= PROGRESS_SECONDS:
            elapsed = now - started
            print(
                f"[incoming-index] counting: {edge_index + 1:,}/{edge_count:,} edges | {elapsed:.1f}s",
                flush=True,
            )
            last_print = now

    offsets = array.array("I", [0]) * (node_count + 1)
    running = 0
    for node_index, count in enumerate(counts):
        offsets[node_index] = running
        running += count
    offsets[node_count] = running
    if running != edge_count:
        raise RuntimeError(f"incoming edge count mismatch: expected {edge_count:,}, got {running:,}")

    cursors = array.array("I", offsets[:-1])
    refs = array.array("I", [0]) * edge_count
    last_print = time.perf_counter()
    phase_started = last_print
    for edge_index in range(edge_count):
        edge = graph.edges[edge_index]
        target = edge.target_index
        position = cursors[target]
        refs[position] = edge_index
        cursors[target] = position + 1
        now = time.perf_counter()
        if now - last_print >= PROGRESS_SECONDS:
            print(
                f"[incoming-index] filling: {edge_index + 1:,}/{edge_count:,} edges | "
                f"{now - phase_started:.1f}s",
                flush=True,
            )
            last_print = now

    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    try:
        with temp.open("wb") as handle:
            handle.write(HEADER.pack(MAGIC, node_count, edge_count))
            if offsets.itemsize != 4 or refs.itemsize != 4:
                raise RuntimeError("BRI1 requires 32-bit unsigned integers")
            if array.array("I", [1]).tobytes() != b"\x01\x00\x00\x00":
                offsets.byteswap()
                refs.byteswap()
            offsets.tofile(handle)
            refs.tofile(handle)
        temp.replace(path)
    except BaseException:
        if temp.exists():
            temp.unlink()
        raise

    elapsed = time.perf_counter() - started
    print(
        f"[incoming-index] done: {node_count:,} nodes, {edge_count:,} refs, "
        f"{path.stat().st_size:,} bytes, {elapsed:.1f}s",
        flush=True,
    )
    return {
        "node_count": node_count,
        "edge_count": edge_count,
        "output_bytes": path.stat().st_size,
        "build_seconds": round(elapsed, 3),
    }


class IncomingEdgeIndex:
    """Memory-mapped BRI1 reverse adjacency for bidirectional routing."""

    def __init__(self, path: Path, expected_node_count: int | None = None, expected_edge_count: int | None = None) -> None:
        self.path = Path(path)
        self._file = self.path.open("rb")
        try:
            self._map = mmap.mmap(self._file.fileno(), 0, access=mmap.ACCESS_READ)
            if len(self._map) < HEADER.size:
                raise ValueError("BRI1 header is truncated")
            magic, self.node_count, self.edge_count = HEADER.unpack_from(self._map, 0)
            if magic != MAGIC:
                raise ValueError(f"Unsupported incoming index magic: {magic!r}")
            if expected_node_count is not None and self.node_count != expected_node_count:
                raise ValueError("BRI1 node count does not match BRG1")
            if expected_edge_count is not None and self.edge_count != expected_edge_count:
                raise ValueError("BRI1 edge count does not match BRG1")
            self._offsets_offset = HEADER.size
            self._refs_offset = self._offsets_offset + (self.node_count + 1) * UINT32.size
            expected = self._refs_offset + self.edge_count * UINT32.size
            if len(self._map) != expected:
                raise ValueError(f"BRI1 file size mismatch: expected {expected}, got {len(self._map)}")
        except Exception:
            self._file.close()
            raise

    def incoming_edges(self, node_index: int) -> Iterator[int]:
        if not 0 <= node_index < self.node_count:
            raise IndexError(node_index)
        start = UINT32.unpack_from(self._map, self._offsets_offset + node_index * UINT32.size)[0]
        end = UINT32.unpack_from(self._map, self._offsets_offset + (node_index + 1) * UINT32.size)[0]
        for position in range(start, end):
            yield UINT32.unpack_from(self._map, self._refs_offset + position * UINT32.size)[0]

    def close(self) -> None:
        if getattr(self, "_map", None) is not None:
            self._map.close()
            self._map = None
        if getattr(self, "_file", None) is not None:
            self._file.close()
            self._file = None

    def __enter__(self) -> "IncomingEdgeIndex":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()
