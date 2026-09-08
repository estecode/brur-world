"""A* specialization for fast GPS routing on large BRG1 graphs.

Dependencies:
- gps_routing.py owns route reconstruction, snapping semantics and edge costs.
- routing_graph.py provides true geodesic node coordinates.
- The maximum legal speed bound comes from the offline BRS2 snap index.
"""

from __future__ import annotations

import heapq
import math

from gps_routing import (
    DirectedSnap,
    EdgeCostPolicy,
    GraphRouter,
    RoadSnap,
    RouteResult,
    RouteStep,
    RoutingPreference,
    _pick_better,
    route_metrics,
)
from routing_graph import geodesic_distance_m, is_edge_allowed


class AStarGraphRouter(GraphRouter):
    """GraphRouter with an admissible distance/time heuristic.

    For shortest routes, straight-line metres are a lower bound. For fastest and
    avoidance preferences, straight-line travel time at the fastest legal edge
    speed is a lower bound; avoidance penalties only increase the true cost.

    Snapped road positions are routed with one multi-source/multi-target search
    instead of one whole-graph search for every direction pair.
    """

    def __init__(self, graph, profile, max_legal_speed_kmh: float) -> None:
        super().__init__(graph, profile)
        if max_legal_speed_kmh <= 0.0:
            raise ValueError("max_legal_speed_kmh must be positive")
        self.max_legal_speed_kmh = float(max_legal_speed_kmh)
        self.last_stats: dict[str, int] = {}

    def _heuristic(self, node_index: int, target_index: int, policy: EdgeCostPolicy) -> float:
        a = self.graph.nodes[node_index]
        b = self.graph.nodes[target_index]
        distance_m = geodesic_distance_m((a.lon, a.lat), (b.lon, b.lat))
        if policy.preference == RoutingPreference.SHORTEST:
            return distance_m
        max_speed_mps = self.max_legal_speed_kmh / 3.6
        return distance_m / max_speed_mps

    def _heuristic_to_targets(
        self,
        node_index: int,
        target_nodes: tuple[int, ...],
        policy: EdgeCostPolicy,
    ) -> float:
        if not target_nodes:
            return 0.0
        return min(self._heuristic(node_index, target, policy) for target in target_nodes)

    def route_nodes(self, start_index: int, target_index: int, policy: EdgeCostPolicy) -> RouteResult:
        self.last_stats = {"settled": 0, "relaxed": 0, "queue_peak": 1, "searches": 1}
        node_count = len(self.graph.nodes)
        if not (0 <= start_index < node_count and 0 <= target_index < node_count):
            return RouteResult(False, failure_reason="invalid_node")
        if start_index == target_index:
            return RouteResult(True, cost=0.0)

        best: dict[int, float] = {start_index: 0.0}
        came_from: dict[int, tuple[int, int]] = {}
        queue: list[tuple[float, float, int]] = [
            (self._heuristic(start_index, target_index, policy), 0.0, start_index)
        ]

        while queue:
            _, current_cost, node_index = heapq.heappop(queue)
            if current_cost != best.get(node_index):
                continue
            self.last_stats["settled"] += 1
            if node_index == target_index:
                return self._reconstruct(start_index, target_index, came_from, current_cost)

            node = self.graph.nodes[node_index]
            start = node.adjacency_offset
            end = start + node.adjacency_count
            for edge_index in range(start, end):
                edge = self.graph.edges[edge_index]
                if not is_edge_allowed(edge, self.profile):
                    continue
                self.last_stats["relaxed"] += 1
                candidate = current_cost + policy.edge_cost(edge)
                previous = best.get(edge.target_index)
                if previous is None or candidate < previous - 1e-12:
                    best[edge.target_index] = candidate
                    came_from[edge.target_index] = (node_index, edge_index)
                    estimate = candidate + self._heuristic(edge.target_index, target_index, policy)
                    heapq.heappush(queue, (estimate, candidate, edge.target_index))
                    self.last_stats["queue_peak"] = max(self.last_stats["queue_peak"], len(queue))
                elif previous is not None and abs(candidate - previous) <= 1e-12:
                    old = came_from.get(edge.target_index)
                    if old is not None and edge_index < old[1]:
                        came_from[edge.target_index] = (node_index, edge_index)

        return RouteResult(False, failure_reason="unreachable")

    def route_snaps(self, start: RoadSnap, destination: RoadSnap, policy: EdgeCostPolicy) -> RouteResult:
        """Route all legal snap directions with one A* search."""
        if not start.directions:
            return RouteResult(False, failure_reason="unreachable_start")
        if not destination.directions:
            return RouteResult(False, failure_reason="unreachable_destination")

        best_result: RouteResult | None = None
        for start_snap in start.directions:
            for destination_snap in destination.directions:
                direct = self._same_edge_route(start_snap, destination_snap, policy)
                if direct is not None:
                    best_result = _pick_better(best_result, direct)

        starts: list[tuple[int, float, DirectedSnap]] = []
        targets_by_node: dict[int, list[tuple[float, DirectedSnap]]] = {}

        for snap in start.directions:
            edge = self.graph.edges[snap.edge_index]
            if not is_edge_allowed(edge, self.profile):
                continue
            starts.append((edge.target_index, policy.edge_cost(edge) * max(0.0, 1.0 - snap.fraction), snap))

        for snap in destination.directions:
            edge = self.graph.edges[snap.edge_index]
            if not is_edge_allowed(edge, self.profile):
                continue
            targets_by_node.setdefault(edge.source_index, []).append(
                (policy.edge_cost(edge) * max(0.0, snap.fraction), snap)
            )

        if not starts or not targets_by_node:
            return best_result or RouteResult(False, failure_reason="unreachable")

        target_nodes = tuple(sorted(targets_by_node))
        best: dict[int, float] = {}
        came_from: dict[int, tuple[int, int]] = {}
        seed_snap: dict[int, DirectedSnap] = {}
        queue: list[tuple[float, float, int]] = []

        for node_index, initial_cost, snap in sorted(starts, key=lambda item: (item[1], item[2].edge_index)):
            previous = best.get(node_index)
            if previous is None or initial_cost < previous - 1e-12 or (
                abs(initial_cost - previous) <= 1e-12 and snap.edge_index < seed_snap[node_index].edge_index
            ):
                best[node_index] = initial_cost
                seed_snap[node_index] = snap
                estimate = initial_cost + self._heuristic_to_targets(node_index, target_nodes, policy)
                heapq.heappush(queue, (estimate, initial_cost, node_index))

        self.last_stats = {"settled": 0, "relaxed": 0, "queue_peak": len(queue), "searches": 1}
        best_total = best_result.cost if best_result is not None else math.inf
        best_target_node: int | None = None
        best_target_snap: DirectedSnap | None = None

        while queue:
            estimate, current_cost, node_index = heapq.heappop(queue)
            if current_cost != best.get(node_index):
                continue
            if estimate >= best_total - 1e-12:
                break
            self.last_stats["settled"] += 1

            for terminal_cost, target_snap in targets_by_node.get(node_index, ()):
                total = current_cost + terminal_cost
                if total < best_total - 1e-12 or (
                    abs(total - best_total) <= 1e-12
                    and (best_target_snap is None or target_snap.edge_index < best_target_snap.edge_index)
                ):
                    best_total = total
                    best_target_node = node_index
                    best_target_snap = target_snap

            node = self.graph.nodes[node_index]
            for edge_index in range(node.adjacency_offset, node.adjacency_offset + node.adjacency_count):
                edge = self.graph.edges[edge_index]
                if not is_edge_allowed(edge, self.profile):
                    continue
                self.last_stats["relaxed"] += 1
                candidate = current_cost + policy.edge_cost(edge)
                previous = best.get(edge.target_index)
                if previous is None or candidate < previous - 1e-12:
                    best[edge.target_index] = candidate
                    came_from[edge.target_index] = (node_index, edge_index)
                    estimate = candidate + self._heuristic_to_targets(edge.target_index, target_nodes, policy)
                    if estimate < best_total - 1e-12:
                        heapq.heappush(queue, (estimate, candidate, edge.target_index))
                        self.last_stats["queue_peak"] = max(self.last_stats["queue_peak"], len(queue))
                elif previous is not None and abs(candidate - previous) <= 1e-12:
                    old = came_from.get(edge.target_index)
                    if old is not None and edge_index < old[1]:
                        came_from[edge.target_index] = (node_index, edge_index)

        if best_target_node is None or best_target_snap is None:
            return best_result or RouteResult(False, failure_reason="unreachable")

        middle_edges: list[int] = []
        current = best_target_node
        while current not in seed_snap or current in came_from:
            previous = came_from.get(current)
            if previous is None:
                return best_result or RouteResult(False, failure_reason="broken_path")
            current, edge_index = previous
            middle_edges.append(edge_index)
        middle_edges.reverse()
        start_snap = seed_snap[current]

        steps: list[RouteStep] = []
        if start_snap.fraction < 1.0 - 1e-12:
            steps.append(RouteStep(start_snap.edge_index, start_snap.fraction, 1.0))
        steps.extend(RouteStep(edge_index) for edge_index in middle_edges)
        if best_target_snap.fraction > 1e-12:
            steps.append(RouteStep(best_target_snap.edge_index, 0.0, best_target_snap.fraction))

        packed = tuple(steps)
        distance_m, travel_time_s = route_metrics(self.graph, packed)
        routed = RouteResult(True, packed, best_total, distance_m, travel_time_s)
        return _pick_better(best_result, routed)
