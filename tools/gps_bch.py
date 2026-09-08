"""Serialize and query a compact mmap-backed BCH1 contraction-hierarchy sidecar.

Dependencies:
- gps_ch.py owns the fixture-scale correctness builder and CHIndex model.
- gps_routing.py owns route result data and edge-cost policy.
- routing_graph.py / routing_graph_view.py own BRG1 graph data and route metrics.

BCH1 is the first binary correctness checkpoint for production CH acceleration.
It is pointer-free, explicitly little-endian and keeps hot CSR references separate
from cold shortcut decomposition. The current Python query uses sparse dict/heap
state; production fixed-capacity RoutingContext work comes after this format and
mmap query are proven exact.
"""

from __future__ import annotations

import heapq
import math
import mmap
import struct
from pathlib import Path

from gps_ch import CHIndex
from gps_routing import EdgeCostPolicy, GraphRouter, RouteResult, RouteStep, RoutingPreference, route_metrics
from routing_graph import RoutingProfile


MAGIC = b"BCH1"
VERSION = 1
HEADER = struct.Struct("<4sIIIIIIIfQQQQQQ")
EDGE = struct.Struct("<IIdiii")
U32 = struct.Struct("<I")

_PREFERENCE_TO_CODE = {
    RoutingPreference.FASTEST: 0,
    RoutingPreference.SHORTEST: 1,
    RoutingPreference.AVOID_SMALL_ROADS: 2,
    RoutingPreference.AVOID_MAJOR_ROADS: 3,
}
_CODE_TO_PREFERENCE = {value: key for key, value in _PREFERENCE_TO_CODE.items()}


def _flatten_csr(rows: tuple[tuple[int, ...], ...]) -> tuple[list[int], list[int]]:
    offsets = [0]
    refs: list[int] = []
    for row in rows:
        refs.extend(row)
        offsets.append(len(refs))
    return offsets, refs


def write_bch(index: CHIndex, path: Path) -> dict[str, int]:
    """Write one metric-specific CHIndex to a portable BCH1 sidecar."""
    node_count = len(index.rank)
    if len(index.upward_out) != node_count or len(index.downward_in) != node_count:
        raise ValueError("CH index CSR rows do not match node count")

    up_offsets, up_refs = _flatten_csr(index.upward_out)
    down_offsets, down_refs = _flatten_csr(index.downward_in)
    edge_count = len(index.edges)

    rank_offset = HEADER.size
    edge_offset = rank_offset + node_count * U32.size
    up_offsets_offset = edge_offset + edge_count * EDGE.size
    up_refs_offset = up_offsets_offset + (node_count + 1) * U32.size
    down_offsets_offset = up_refs_offset + len(up_refs) * U32.size
    down_refs_offset = down_offsets_offset + (node_count + 1) * U32.size

    preference_code = _PREFERENCE_TO_CODE[index.preference]
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    try:
        with temp.open("wb") as handle:
            handle.write(
                HEADER.pack(
                    MAGIC,
                    VERSION,
                    node_count,
                    edge_count,
                    len(up_refs),
                    len(down_refs),
                    preference_code,
                    0,
                    float(index.avoid_penalty),
                    rank_offset,
                    edge_offset,
                    up_offsets_offset,
                    up_refs_offset,
                    down_offsets_offset,
                    down_refs_offset,
                )
            )
            for rank in index.rank:
                handle.write(U32.pack(rank))
            for edge in index.edges:
                handle.write(
                    EDGE.pack(
                        edge.source_index,
                        edge.target_index,
                        edge.cost,
                        edge.original_edge_index,
                        edge.left_child,
                        edge.right_child,
                    )
                )
            for value in up_offsets:
                handle.write(U32.pack(value))
            for value in up_refs:
                handle.write(U32.pack(value))
            for value in down_offsets:
                handle.write(U32.pack(value))
            for value in down_refs:
                handle.write(U32.pack(value))
        temp.replace(path)
    except BaseException:
        if temp.exists():
            temp.unlink()
        raise

    return {
        "node_count": node_count,
        "edge_count": edge_count,
        "upward_reference_count": len(up_refs),
        "downward_reference_count": len(down_refs),
        "output_bytes": path.stat().st_size,
    }


class PersistentCHRouter(GraphRouter):
    """Read BCH1 directly from mmap and return original BRG1 route edges."""

    def __init__(self, graph, profile: RoutingProfile, path: Path) -> None:
        super().__init__(graph, profile)
        self.path = Path(path)
        self._file = self.path.open("rb")
        self._map = None
        try:
            self._map = mmap.mmap(self._file.fileno(), 0, access=mmap.ACCESS_READ)
            if len(self._map) < HEADER.size:
                raise ValueError("BCH1 header is truncated")
            (
                magic,
                version,
                self.node_count,
                self.edge_count,
                self.up_ref_count,
                self.down_ref_count,
                preference_code,
                _reserved,
                self.avoid_penalty,
                self.rank_offset,
                self.edge_offset,
                self.up_offsets_offset,
                self.up_refs_offset,
                self.down_offsets_offset,
                self.down_refs_offset,
            ) = HEADER.unpack_from(self._map, 0)
            if magic != MAGIC or version != VERSION:
                raise ValueError(f"Unsupported BCH sidecar: magic={magic!r}, version={version}")
            if self.node_count != len(graph.nodes):
                raise ValueError("BCH1 node count does not match routing graph")
            try:
                self.preference = _CODE_TO_PREFERENCE[preference_code]
            except KeyError as exc:
                raise ValueError(f"BCH1 has unknown routing preference code {preference_code}") from exc
            self._validate_layout()
        except Exception:
            if self._map is not None:
                self._map.close()
                self._map = None
            self._file.close()
            raise

    def _validate_layout(self) -> None:
        expected_rank = HEADER.size
        expected_edge = expected_rank + self.node_count * U32.size
        expected_up_offsets = expected_edge + self.edge_count * EDGE.size
        expected_up_refs = expected_up_offsets + (self.node_count + 1) * U32.size
        expected_down_offsets = expected_up_refs + self.up_ref_count * U32.size
        expected_down_refs = expected_down_offsets + (self.node_count + 1) * U32.size
        expected_size = expected_down_refs + self.down_ref_count * U32.size
        actual = (
            self.rank_offset,
            self.edge_offset,
            self.up_offsets_offset,
            self.up_refs_offset,
            self.down_offsets_offset,
            self.down_refs_offset,
        )
        expected = (
            expected_rank,
            expected_edge,
            expected_up_offsets,
            expected_up_refs,
            expected_down_offsets,
            expected_down_refs,
        )
        if actual != expected or len(self._map) != expected_size:
            raise ValueError("BCH1 layout/file size mismatch")

    def close(self) -> None:
        if self._map is not None:
            self._map.close()
            self._map = None
        if self._file is not None:
            self._file.close()
            self._file = None

    def __enter__(self) -> "PersistentCHRouter":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def _check_policy(self, policy: EdgeCostPolicy) -> None:
        if policy.preference != self.preference or abs(policy.avoid_penalty - self.avoid_penalty) > 1e-6:
            raise ValueError("BCH1 metric does not match requested routing policy")

    def _edge(self, edge_index: int) -> tuple[int, int, float, int, int, int]:
        if not 0 <= edge_index < self.edge_count:
            raise ValueError("BCH1 edge reference out of range")
        return EDGE.unpack_from(self._map, self.edge_offset + edge_index * EDGE.size)

    def _refs(self, node_index: int, offsets_base: int, refs_base: int, ref_count: int):
        start = U32.unpack_from(self._map, offsets_base + node_index * U32.size)[0]
        end = U32.unpack_from(self._map, offsets_base + (node_index + 1) * U32.size)[0]
        if start > end or end > ref_count:
            raise ValueError("BCH1 CSR range is invalid")
        for position in range(start, end):
            yield U32.unpack_from(self._map, refs_base + position * U32.size)[0]

    def _upward_refs(self, node_index: int):
        return self._refs(node_index, self.up_offsets_offset, self.up_refs_offset, self.up_ref_count)

    def _downward_refs(self, node_index: int):
        return self._refs(node_index, self.down_offsets_offset, self.down_refs_offset, self.down_ref_count)

    def route_nodes(self, start_index: int, target_index: int, policy: EdgeCostPolicy) -> RouteResult:
        self._check_policy(policy)
        if not (0 <= start_index < self.node_count and 0 <= target_index < self.node_count):
            return RouteResult(False, failure_reason="invalid_node")
        if start_index == target_index:
            return RouteResult(True, cost=0.0)

        forward_best: dict[int, float] = {start_index: 0.0}
        backward_best: dict[int, float] = {target_index: 0.0}
        forward_prev: dict[int, tuple[int, int]] = {}
        backward_next: dict[int, tuple[int, int]] = {}
        forward_queue: list[tuple[float, int]] = [(0.0, start_index)]
        backward_queue: list[tuple[float, int]] = [(0.0, target_index)]
        best_path = math.inf
        meeting: int | None = None

        while forward_queue or backward_queue:
            if forward_queue:
                cost, node_index = heapq.heappop(forward_queue)
                if cost == forward_best.get(node_index) and cost <= best_path + 1e-12:
                    other = backward_best.get(node_index)
                    if other is not None:
                        total = cost + other
                        if total < best_path - 1e-12 or (
                            abs(total - best_path) <= 1e-12 and (meeting is None or node_index < meeting)
                        ):
                            best_path, meeting = total, node_index
                    for edge_index in self._upward_refs(node_index):
                        _source, target, edge_cost, _original, _left, _right = self._edge(edge_index)
                        candidate = cost + edge_cost
                        previous = forward_best.get(target)
                        if previous is None or candidate < previous - 1e-12:
                            forward_best[target] = candidate
                            forward_prev[target] = (node_index, edge_index)
                            heapq.heappush(forward_queue, (candidate, target))

            if backward_queue:
                cost, node_index = heapq.heappop(backward_queue)
                if cost == backward_best.get(node_index) and cost <= best_path + 1e-12:
                    other = forward_best.get(node_index)
                    if other is not None:
                        total = cost + other
                        if total < best_path - 1e-12 or (
                            abs(total - best_path) <= 1e-12 and (meeting is None or node_index < meeting)
                        ):
                            best_path, meeting = total, node_index
                    for edge_index in self._downward_refs(node_index):
                        source, _target, edge_cost, _original, _left, _right = self._edge(edge_index)
                        candidate = cost + edge_cost
                        previous = backward_best.get(source)
                        if previous is None or candidate < previous - 1e-12:
                            backward_best[source] = candidate
                            backward_next[source] = (node_index, edge_index)
                            heapq.heappush(backward_queue, (candidate, source))

        if meeting is None:
            return RouteResult(False, failure_reason="unreachable")

        ch_edges: list[int] = []
        current = meeting
        before: list[int] = []
        while current != start_index:
            previous = forward_prev.get(current)
            if previous is None:
                return RouteResult(False, failure_reason="broken_path")
            current, edge_index = previous
            before.append(edge_index)
        before.reverse()
        ch_edges.extend(before)

        current = meeting
        while current != target_index:
            next_step = backward_next.get(current)
            if next_step is None:
                return RouteResult(False, failure_reason="broken_path")
            current, edge_index = next_step
            ch_edges.append(edge_index)

        original_edges: list[int] = []
        for edge_index in ch_edges:
            self._unpack(edge_index, original_edges)
        steps = tuple(RouteStep(edge_index) for edge_index in original_edges)
        distance_m, travel_time_s = route_metrics(self.graph, steps)
        return RouteResult(True, steps, best_path, distance_m, travel_time_s)

    def _unpack(self, edge_index: int, output: list[int]) -> None:
        _source, _target, _cost, original, left, right = self._edge(edge_index)
        if original >= 0:
            output.append(original)
            return
        self._unpack(left, output)
        self._unpack(right, output)
