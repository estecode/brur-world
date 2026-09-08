"""Exact bidirectional GPS routing over BRG1 plus BRI1 reverse adjacency.

Dependencies:
- gps_routing.py owns route data, snapping semantics and edge-cost policy.
- gps_incoming_index.py supplies incoming edges without expanding reverse adjacency.
- This module owns only the bidirectional path search.
"""

from __future__ import annotations

import heapq
import math

from gps_routing import EdgeCostPolicy, GraphRouter, RouteResult, RouteStep, route_metrics
from routing_graph import is_edge_allowed


class BidirectionalGraphRouter(GraphRouter):
    """Deterministic exact bidirectional Dijkstra for large routing graphs."""

    def __init__(self, graph, profile, incoming_index) -> None:
        super().__init__(graph, profile)
        self.incoming_index = incoming_index
        if incoming_index.node_count != len(graph.nodes) or incoming_index.edge_count != len(graph.edges):
            raise ValueError("incoming index does not match routing graph")

    def route_nodes(self, start_index: int, target_index: int, policy: EdgeCostPolicy) -> RouteResult:
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
        forward_settled: set[int] = set()
        backward_settled: set[int] = set()

        best_path = math.inf
        meeting: int | None = None

        while forward_queue and backward_queue:
            while forward_queue and forward_queue[0][0] != forward_best.get(forward_queue[0][1]):
                heapq.heappop(forward_queue)
            while backward_queue and backward_queue[0][0] != backward_best.get(backward_queue[0][1]):
                heapq.heappop(backward_queue)
            if not forward_queue or not backward_queue:
                break
            if forward_queue[0][0] + backward_queue[0][0] >= best_path - 1e-12:
                break

            expand_forward = forward_queue[0][0] <= backward_queue[0][0]
            if expand_forward:
                current_cost, node_index = heapq.heappop(forward_queue)
                if node_index in forward_settled:
                    continue
                forward_settled.add(node_index)
                other = backward_best.get(node_index)
                if other is not None:
                    total = current_cost + other
                    if total < best_path - 1e-12 or (abs(total - best_path) <= 1e-12 and (meeting is None or node_index < meeting)):
                        best_path = total
                        meeting = node_index

                node = self.graph.nodes[node_index]
                for edge_index in range(node.adjacency_offset, node.adjacency_offset + node.adjacency_count):
                    edge = self.graph.edges[edge_index]
                    if not is_edge_allowed(edge, self.profile):
                        continue
                    candidate = current_cost + policy.edge_cost(edge)
                    previous = forward_best.get(edge.target_index)
                    if previous is None or candidate < previous - 1e-12:
                        forward_best[edge.target_index] = candidate
                        forward_prev[edge.target_index] = (node_index, edge_index)
                        heapq.heappush(forward_queue, (candidate, edge.target_index))
                    elif previous is not None and abs(candidate - previous) <= 1e-12:
                        old = forward_prev.get(edge.target_index)
                        if old is not None and edge_index < old[1]:
                            forward_prev[edge.target_index] = (node_index, edge_index)
                    other = backward_best.get(edge.target_index)
                    if other is not None:
                        total = candidate + other
                        if total < best_path - 1e-12 or (abs(total - best_path) <= 1e-12 and (meeting is None or edge.target_index < meeting)):
                            best_path = total
                            meeting = edge.target_index
            else:
                current_cost, node_index = heapq.heappop(backward_queue)
                if node_index in backward_settled:
                    continue
                backward_settled.add(node_index)
                other = forward_best.get(node_index)
                if other is not None:
                    total = current_cost + other
                    if total < best_path - 1e-12 or (abs(total - best_path) <= 1e-12 and (meeting is None or node_index < meeting)):
                        best_path = total
                        meeting = node_index

                for edge_index in self.incoming_index.incoming_edges(node_index):
                    edge = self.graph.edges[edge_index]
                    if not is_edge_allowed(edge, self.profile):
                        continue
                    candidate = current_cost + policy.edge_cost(edge)
                    previous = backward_best.get(edge.source_index)
                    if previous is None or candidate < previous - 1e-12:
                        backward_best[edge.source_index] = candidate
                        backward_next[edge.source_index] = (node_index, edge_index)
                        heapq.heappush(backward_queue, (candidate, edge.source_index))
                    elif previous is not None and abs(candidate - previous) <= 1e-12:
                        old = backward_next.get(edge.source_index)
                        if old is not None and edge_index < old[1]:
                            backward_next[edge.source_index] = (node_index, edge_index)
                    other = forward_best.get(edge.source_index)
                    if other is not None:
                        total = candidate + other
                        if total < best_path - 1e-12 or (abs(total - best_path) <= 1e-12 and (meeting is None or edge.source_index < meeting)):
                            best_path = total
                            meeting = edge.source_index

        if meeting is None or not math.isfinite(best_path):
            return RouteResult(False, failure_reason="unreachable")
        return self._reconstruct_bidirectional(
            start_index,
            target_index,
            meeting,
            forward_prev,
            backward_next,
            best_path,
        )

    def _reconstruct_bidirectional(
        self,
        start_index: int,
        target_index: int,
        meeting: int,
        forward_prev: dict[int, tuple[int, int]],
        backward_next: dict[int, tuple[int, int]],
        cost: float,
    ) -> RouteResult:
        before: list[int] = []
        current = meeting
        while current != start_index:
            previous = forward_prev.get(current)
            if previous is None:
                return RouteResult(False, failure_reason="broken_path")
            current, edge_index = previous
            before.append(edge_index)
        before.reverse()

        after: list[int] = []
        current = meeting
        while current != target_index:
            next_step = backward_next.get(current)
            if next_step is None:
                return RouteResult(False, failure_reason="broken_path")
            current, edge_index = next_step
            after.append(edge_index)

        steps = tuple(RouteStep(edge_index) for edge_index in before + after)
        distance_m, travel_time_s = route_metrics(self.graph, steps)
        return RouteResult(True, steps, cost, distance_m, travel_time_s)
