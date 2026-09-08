"""Route between snapped positions on Brur World's BRG1 road graph.

Dependencies:
- routing_graph.py owns graph data, legality and real metric edge facts.
- This module owns GPS snapping, route cost policy and path search only.
- It has no Godot, player-input, vehicle, traffic or police dependencies.
"""

from __future__ import annotations

import heapq
import math
from dataclasses import dataclass
from enum import Enum
from typing import Iterable

from routing_graph import (
    GraphEdge,
    ROAD_CLASS_NAME,
    RoutingGraph,
    RoutingProfile,
    geodesic_distance_m,
    is_edge_allowed,
)


class RoutingPreference(str, Enum):
    FASTEST = "fastest"
    SHORTEST = "shortest"
    AVOID_SMALL_ROADS = "avoid_small_roads"
    AVOID_MAJOR_ROADS = "avoid_major_roads"


SMALL_ROADS = frozenset({"residential", "service", "track", "unclassified", "living_street", "road"})
MAJOR_ROADS = frozenset({
    "motorway",
    "motorway_link",
    "trunk",
    "trunk_link",
    "primary",
    "primary_link",
})


@dataclass(frozen=True)
class EdgeCostPolicy:
    """Small composable edge-cost policy shared by every route leg."""

    preference: RoutingPreference = RoutingPreference.FASTEST
    avoid_penalty: float = 4.0

    def edge_cost(self, edge: GraphEdge) -> float:
        if self.preference == RoutingPreference.SHORTEST:
            return edge.length_m

        hours = edge.length_m / 1000.0 / edge.speed_kmh
        seconds = hours * 3600.0
        road_name = ROAD_CLASS_NAME[edge.road_class]
        if self.preference == RoutingPreference.AVOID_SMALL_ROADS and road_name in SMALL_ROADS:
            seconds *= self.avoid_penalty
        elif self.preference == RoutingPreference.AVOID_MAJOR_ROADS and road_name in MAJOR_ROADS:
            seconds *= self.avoid_penalty
        return seconds


@dataclass(frozen=True)
class DirectedSnap:
    """One legal travel direction through a physical snapped road position."""

    edge_index: int
    fraction: float


@dataclass(frozen=True)
class RoadSnap:
    x: float
    y: float
    distance_m: float
    directions: tuple[DirectedSnap, ...]

    @property
    def reachable(self) -> bool:
        return bool(self.directions)


@dataclass(frozen=True)
class RouteStep:
    edge_index: int
    start_fraction: float = 0.0
    end_fraction: float = 1.0

    @property
    def fraction(self) -> float:
        return max(0.0, self.end_fraction - self.start_fraction)


@dataclass(frozen=True)
class RouteResult:
    success: bool
    steps: tuple[RouteStep, ...] = ()
    cost: float = math.inf
    distance_m: float = 0.0
    travel_time_s: float = 0.0
    failure_reason: str | None = None


class GraphRouter:
    """Deterministic A* over one RoutingGraph with pluggable edge costs."""

    def __init__(self, graph: RoutingGraph, profile: RoutingProfile = RoutingProfile.NORMAL) -> None:
        self.graph = graph
        self.profile = profile

    def _heuristic(self, node_index: int, target_index: int, policy: EdgeCostPolicy) -> float:
        if policy.preference != RoutingPreference.SHORTEST:
            # A zero time heuristic keeps all speed/avoidance policies correct even when
            # OSM contains unusual explicit speeds. Profile first, then optimize if needed.
            return 0.0
        a = self.graph.nodes[node_index]
        b = self.graph.nodes[target_index]
        return geodesic_distance_m((a.lon, a.lat), (b.lon, b.lat))

    def route_nodes(self, start_index: int, target_index: int, policy: EdgeCostPolicy) -> RouteResult:
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
            if node_index == target_index:
                return self._reconstruct(start_index, target_index, came_from, current_cost)

            node = self.graph.nodes[node_index]
            start = node.adjacency_offset
            end = start + node.adjacency_count
            for edge_index in range(start, end):
                edge = self.graph.edges[edge_index]
                if not is_edge_allowed(edge, self.profile):
                    continue
                candidate = current_cost + policy.edge_cost(edge)
                previous = best.get(edge.target_index)
                if previous is None or candidate < previous - 1e-12:
                    best[edge.target_index] = candidate
                    came_from[edge.target_index] = (node_index, edge_index)
                    estimate = candidate + self._heuristic(edge.target_index, target_index, policy)
                    heapq.heappush(queue, (estimate, candidate, edge.target_index))
                elif previous is not None and abs(candidate - previous) <= 1e-12:
                    # Make equal-cost alternatives reproducible independent of heap history.
                    old = came_from.get(edge.target_index)
                    if old is not None and edge_index < old[1]:
                        came_from[edge.target_index] = (node_index, edge_index)

        return RouteResult(False, failure_reason="unreachable")

    def _reconstruct(
        self,
        start_index: int,
        target_index: int,
        came_from: dict[int, tuple[int, int]],
        cost: float,
    ) -> RouteResult:
        edge_indices: list[int] = []
        current = target_index
        while current != start_index:
            previous = came_from.get(current)
            if previous is None:
                return RouteResult(False, failure_reason="broken_path")
            current, edge_index = previous
            edge_indices.append(edge_index)
        edge_indices.reverse()
        steps = tuple(RouteStep(edge_index) for edge_index in edge_indices)
        distance_m, travel_time_s = route_metrics(self.graph, steps)
        return RouteResult(True, steps, cost, distance_m, travel_time_s)

    def route_snaps(self, start: RoadSnap, destination: RoadSnap, policy: EdgeCostPolicy) -> RouteResult:
        if not start.directions:
            return RouteResult(False, failure_reason="unreachable_start")
        if not destination.directions:
            return RouteResult(False, failure_reason="unreachable_destination")

        best_result: RouteResult | None = None
        for start_snap in start.directions:
            start_edge = self.graph.edges[start_snap.edge_index]
            if not is_edge_allowed(start_edge, self.profile):
                continue
            for destination_snap in destination.directions:
                destination_edge = self.graph.edges[destination_snap.edge_index]
                if not is_edge_allowed(destination_edge, self.profile):
                    continue

                direct = self._same_edge_route(start_snap, destination_snap, policy)
                if direct is not None:
                    best_result = _pick_better(best_result, direct)

                middle = self.route_nodes(start_edge.target_index, destination_edge.source_index, policy)
                if not middle.success:
                    continue

                steps: list[RouteStep] = []
                if start_snap.fraction < 1.0 - 1e-12:
                    steps.append(RouteStep(start_snap.edge_index, start_snap.fraction, 1.0))
                steps.extend(middle.steps)
                if destination_snap.fraction > 1e-12:
                    steps.append(RouteStep(destination_snap.edge_index, 0.0, destination_snap.fraction))

                cost = (
                    policy.edge_cost(start_edge) * max(0.0, 1.0 - start_snap.fraction)
                    + middle.cost
                    + policy.edge_cost(destination_edge) * max(0.0, destination_snap.fraction)
                )
                packed = tuple(steps)
                distance_m, travel_time_s = route_metrics(self.graph, packed)
                candidate = RouteResult(True, packed, cost, distance_m, travel_time_s)
                best_result = _pick_better(best_result, candidate)

        return best_result or RouteResult(False, failure_reason="unreachable")

    def _same_edge_route(
        self,
        start: DirectedSnap,
        destination: DirectedSnap,
        policy: EdgeCostPolicy,
    ) -> RouteResult | None:
        if start.edge_index != destination.edge_index or destination.fraction < start.fraction:
            return None
        edge = self.graph.edges[start.edge_index]
        fraction = destination.fraction - start.fraction
        steps = () if fraction <= 1e-12 else (RouteStep(start.edge_index, start.fraction, destination.fraction),)
        distance_m, travel_time_s = route_metrics(self.graph, steps)
        return RouteResult(True, steps, policy.edge_cost(edge) * fraction, distance_m, travel_time_s)


class RoadSnapIndex:
    """Simple measurable in-memory spatial grid for compressed routing edges.

    The first implementation intentionally indexes the graph directly. Full-Sweden
    construction/query cost is benchmarked before adding a heavier persistent index.
    """

    def __init__(
        self,
        graph: RoutingGraph,
        profile: RoutingProfile = RoutingProfile.NORMAL,
        cell_size_m: float = 1000.0,
    ) -> None:
        if cell_size_m <= 0.0:
            raise ValueError("cell_size_m must be positive")
        self.graph = graph
        self.profile = profile
        self.cell_size_m = float(cell_size_m)
        self._cells: dict[tuple[int, int], list[int]] = {}
        self._physical_directions: dict[tuple[int, int, int, int], list[int]] = {}
        self._build()

    def _physical_key(self, edge: GraphEdge) -> tuple[int, int, int, int]:
        lo = min(edge.source_index, edge.target_index)
        hi = max(edge.source_index, edge.target_index)
        return edge.way_id, edge.segment_index, lo, hi

    def _build(self) -> None:
        representative: dict[tuple[int, int, int, int], int] = {}
        for edge_index, edge in enumerate(self.graph.edges):
            key = self._physical_key(edge)
            self._physical_directions.setdefault(key, []).append(edge_index)
            if key not in representative:
                representative[key] = edge_index

        for edge_index in representative.values():
            edge = self.graph.edges[edge_index]
            a = self.graph.nodes[edge.source_index]
            b = self.graph.nodes[edge.target_index]
            min_cx = math.floor(min(a.x, b.x) / self.cell_size_m)
            max_cx = math.floor(max(a.x, b.x) / self.cell_size_m)
            min_cy = math.floor(min(a.y, b.y) / self.cell_size_m)
            max_cy = math.floor(max(a.y, b.y) / self.cell_size_m)
            for cx in range(min_cx, max_cx + 1):
                for cy in range(min_cy, max_cy + 1):
                    self._cells.setdefault((cx, cy), []).append(edge_index)

    def snap(self, x: float, y: float, max_distance_m: float = 250.0) -> RoadSnap | None:
        if max_distance_m < 0.0:
            raise ValueError("max_distance_m must be non-negative")
        cx = math.floor(x / self.cell_size_m)
        cy = math.floor(y / self.cell_size_m)
        radius = int(math.ceil(max_distance_m / self.cell_size_m)) + 1
        candidates: set[int] = set()
        for ix in range(cx - radius, cx + radius + 1):
            for iy in range(cy - radius, cy + radius + 1):
                candidates.update(self._cells.get((ix, iy), ()))

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
            return None

        distance, representative_index, representative_fraction, px, py = best
        representative_edge = self.graph.edges[representative_index]
        key = self._physical_key(representative_edge)
        directions: list[DirectedSnap] = []
        for edge_index in sorted(self._physical_directions[key]):
            edge = self.graph.edges[edge_index]
            if not is_edge_allowed(edge, self.profile):
                continue
            same_orientation = (
                edge.source_index == representative_edge.source_index
                and edge.target_index == representative_edge.target_index
            )
            fraction = representative_fraction if same_orientation else 1.0 - representative_fraction
            directions.append(DirectedSnap(edge_index, fraction))
        return RoadSnap(px, py, distance, tuple(directions))


def _closest_point(
    px: float,
    py: float,
    ax: float,
    ay: float,
    bx: float,
    by: float,
) -> tuple[float, float, float]:
    dx = bx - ax
    dy = by - ay
    length_sq = dx * dx + dy * dy
    if length_sq <= 0.0:
        return ax, ay, 0.0
    fraction = ((px - ax) * dx + (py - ay) * dy) / length_sq
    fraction = max(0.0, min(1.0, fraction))
    return ax + dx * fraction, ay + dy * fraction, fraction


def route_metrics(graph: RoutingGraph, steps: Iterable[RouteStep]) -> tuple[float, float]:
    distance_m = 0.0
    travel_time_s = 0.0
    for step in steps:
        edge = graph.edges[step.edge_index]
        fraction = step.fraction
        distance = edge.length_m * fraction
        distance_m += distance
        travel_time_s += distance / (edge.speed_kmh / 3.6)
    return distance_m, travel_time_s


def _pick_better(current: RouteResult | None, candidate: RouteResult) -> RouteResult:
    if current is None:
        return candidate
    if candidate.cost < current.cost - 1e-12:
        return candidate
    if abs(candidate.cost - current.cost) <= 1e-12:
        candidate_key = tuple((step.edge_index, step.start_fraction, step.end_fraction) for step in candidate.steps)
        current_key = tuple((step.edge_index, step.start_fraction, step.end_fraction) for step in current.steps)
        if candidate_key < current_key:
            return candidate
    return current
