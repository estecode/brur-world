"""Build and query an exact contraction hierarchy for GPS routing.

Dependencies:
- gps_routing.py owns route result data, snap semantics and edge-cost policy.
- routing_graph.py owns BRG1 topology and legality.
- This first implementation is deliberately simple and test-oriented: it proves
  CH correctness and shortcut unpacking before Sweden-scale preprocessing is
  moved into a compact offline builder/runtime format.
"""

from __future__ import annotations

import heapq
import math
from dataclasses import dataclass

from gps_routing import EdgeCostPolicy, GraphRouter, RouteResult, RouteStep, RoutingPreference, route_metrics
from routing_graph import RoutingProfile, is_edge_allowed


@dataclass(frozen=True)
class CHEdge:
    source_index: int
    target_index: int
    cost: float
    original_edge_index: int = -1
    left_child: int = -1
    right_child: int = -1

    @property
    def shortcut(self) -> bool:
        return self.original_edge_index < 0


@dataclass(frozen=True)
class CHIndex:
    """Metric-specific exact CH used as the correctness reference for BCH/CCH."""

    rank: tuple[int, ...]
    edges: tuple[CHEdge, ...]
    upward_out: tuple[tuple[int, ...], ...]
    downward_in: tuple[tuple[int, ...], ...]
    preference: RoutingPreference
    avoid_penalty: float


class _MutableCH:
    def __init__(self, graph, profile: RoutingProfile, policy: EdgeCostPolicy) -> None:
        self.graph = graph
        self.profile = profile
        self.policy = policy
        self.node_count = len(graph.nodes)
        self.active = [True] * self.node_count
        self.rank = [-1] * self.node_count
        self.edges: list[CHEdge] = []
        self.outgoing: list[list[int]] = [[] for _ in range(self.node_count)]
        self.incoming: list[list[int]] = [[] for _ in range(self.node_count)]

        for edge_index, edge in enumerate(graph.edges):
            if not is_edge_allowed(edge, profile):
                continue
            self._add_edge(
                CHEdge(
                    edge.source_index,
                    edge.target_index,
                    policy.edge_cost(edge),
                    original_edge_index=edge_index,
                )
            )

    def _add_edge(self, edge: CHEdge) -> int:
        index = len(self.edges)
        self.edges.append(edge)
        self.outgoing[edge.source_index].append(index)
        self.incoming[edge.target_index].append(index)
        return index

    def _active_incoming(self, node_index: int) -> list[int]:
        return [
            edge_index
            for edge_index in self.incoming[node_index]
            if self.active[self.edges[edge_index].source_index]
        ]

    def _active_outgoing(self, node_index: int) -> list[int]:
        return [
            edge_index
            for edge_index in self.outgoing[node_index]
            if self.active[self.edges[edge_index].target_index]
        ]

    def importance(self, node_index: int) -> tuple[int, int, int]:
        """Cheap deterministic ordering metric; ordering affects size, not correctness."""
        incoming = self._active_incoming(node_index)
        outgoing = self._active_outgoing(node_index)
        possible_shortcuts = sum(
            1
            for in_index in incoming
            for out_index in outgoing
            if self.edges[in_index].source_index != self.edges[out_index].target_index
        )
        removed = len(incoming) + len(outgoing)
        return possible_shortcuts - removed, removed, node_index

    def witness_distance(self, source: int, target: int, forbidden: int, limit: float) -> float:
        """Exact bounded Dijkstra over the currently uncontracted graph."""
        if source == target:
            return 0.0
        best: dict[int, float] = {source: 0.0}
        queue: list[tuple[float, int]] = [(0.0, source)]
        while queue:
            cost, node_index = heapq.heappop(queue)
            if cost != best.get(node_index):
                continue
            if cost > limit + 1e-12:
                break
            if node_index == target:
                return cost
            for edge_index in self.outgoing[node_index]:
                edge = self.edges[edge_index]
                next_node = edge.target_index
                if next_node == forbidden or not self.active[next_node]:
                    continue
                candidate = cost + edge.cost
                if candidate > limit + 1e-12:
                    continue
                previous = best.get(next_node)
                if previous is None or candidate < previous - 1e-12:
                    best[next_node] = candidate
                    heapq.heappush(queue, (candidate, next_node))
        return math.inf

    def contract(self, node_index: int, rank: int) -> None:
        incoming = self._active_incoming(node_index)
        outgoing = self._active_outgoing(node_index)
        for in_index in incoming:
            incoming_edge = self.edges[in_index]
            source = incoming_edge.source_index
            if source == node_index:
                continue
            for out_index in outgoing:
                outgoing_edge = self.edges[out_index]
                target = outgoing_edge.target_index
                if target == node_index or source == target:
                    continue
                via_cost = incoming_edge.cost + outgoing_edge.cost
                witness = self.witness_distance(source, target, node_index, via_cost)
                if witness <= via_cost + 1e-12:
                    continue
                self._add_edge(
                    CHEdge(
                        source,
                        target,
                        via_cost,
                        left_child=in_index,
                        right_child=out_index,
                    )
                )
        self.active[node_index] = False
        self.rank[node_index] = rank

    def finish(self) -> CHIndex:
        upward_out: list[list[int]] = [[] for _ in range(self.node_count)]
        downward_in: list[list[int]] = [[] for _ in range(self.node_count)]
        for edge_index, edge in enumerate(self.edges):
            source_rank = self.rank[edge.source_index]
            target_rank = self.rank[edge.target_index]
            if source_rank < target_rank:
                upward_out[edge.source_index].append(edge_index)
            elif source_rank > target_rank:
                # Backward CH search walks these edges in reverse, from lower to higher rank.
                downward_in[edge.target_index].append(edge_index)
        for items in upward_out:
            items.sort()
        for items in downward_in:
            items.sort()
        return CHIndex(
            tuple(self.rank),
            tuple(self.edges),
            tuple(tuple(items) for items in upward_out),
            tuple(tuple(items) for items in downward_in),
            self.policy.preference,
            self.policy.avoid_penalty,
        )


def build_ch(graph, profile: RoutingProfile, policy: EdgeCostPolicy) -> CHIndex:
    """Build an exact metric-specific CH. Intended for fixtures until BCH1 is ready."""
    mutable = _MutableCH(graph, profile, policy)
    remaining = set(range(len(graph.nodes)))
    for rank in range(len(graph.nodes)):
        node_index = min(remaining, key=mutable.importance)
        mutable.contract(node_index, rank)
        remaining.remove(node_index)
    return mutable.finish()


class CHGraphRouter(GraphRouter):
    """Exact bidirectional upward CH query with shortcut unpacking to BRG1 edges."""

    def __init__(self, graph, profile: RoutingProfile, index: CHIndex) -> None:
        super().__init__(graph, profile)
        if len(index.rank) != len(graph.nodes):
            raise ValueError("CH index does not match routing graph")
        self.index = index

    def _check_policy(self, policy: EdgeCostPolicy) -> None:
        if policy.preference != self.index.preference or abs(policy.avoid_penalty - self.index.avoid_penalty) > 1e-12:
            raise ValueError("CH index metric does not match requested routing policy")

    def route_nodes(self, start_index: int, target_index: int, policy: EdgeCostPolicy) -> RouteResult:
        self._check_policy(policy)
        node_count = len(self.graph.nodes)
        if not (0 <= start_index < node_count and 0 <= target_index < node_count):
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
                        if total < best_path - 1e-12 or (abs(total - best_path) <= 1e-12 and (meeting is None or node_index < meeting)):
                            best_path, meeting = total, node_index
                    for edge_index in self.index.upward_out[node_index]:
                        edge = self.index.edges[edge_index]
                        candidate = cost + edge.cost
                        previous = forward_best.get(edge.target_index)
                        if previous is None or candidate < previous - 1e-12:
                            forward_best[edge.target_index] = candidate
                            forward_prev[edge.target_index] = (node_index, edge_index)
                            heapq.heappush(forward_queue, (candidate, edge.target_index))

            if backward_queue:
                cost, node_index = heapq.heappop(backward_queue)
                if cost == backward_best.get(node_index) and cost <= best_path + 1e-12:
                    other = forward_best.get(node_index)
                    if other is not None:
                        total = cost + other
                        if total < best_path - 1e-12 or (abs(total - best_path) <= 1e-12 and (meeting is None or node_index < meeting)):
                            best_path, meeting = total, node_index
                    for edge_index in self.index.downward_in[node_index]:
                        edge = self.index.edges[edge_index]
                        candidate = cost + edge.cost
                        previous = backward_best.get(edge.source_index)
                        if previous is None or candidate < previous - 1e-12:
                            backward_best[edge.source_index] = candidate
                            backward_next[edge.source_index] = (node_index, edge_index)
                            heapq.heappush(backward_queue, (candidate, edge.source_index))

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
        edge = self.index.edges[edge_index]
        if not edge.shortcut:
            output.append(edge.original_edge_index)
            return
        self._unpack(edge.left_child, output)
        self._unpack(edge.right_child, output)
