"""A* specialization for fast GPS routing on large BRG1 graphs.

Dependencies:
- gps_routing.py owns route reconstruction, snapping semantics and edge costs.
- routing_graph.py provides true geodesic node coordinates.
- The maximum legal speed bound comes from the offline BRS2 snap index.
"""

from __future__ import annotations

from gps_routing import EdgeCostPolicy, GraphRouter, RoutingPreference
from routing_graph import geodesic_distance_m


class AStarGraphRouter(GraphRouter):
    """GraphRouter with an admissible distance/time heuristic.

    For shortest routes, straight-line metres are a lower bound. For fastest and
    avoidance preferences, straight-line travel time at the fastest legal edge
    speed is a lower bound; avoidance penalties only increase the true cost.
    """

    def __init__(self, graph, profile, max_legal_speed_kmh: float) -> None:
        super().__init__(graph, profile)
        if max_legal_speed_kmh <= 0.0:
            raise ValueError("max_legal_speed_kmh must be positive")
        self.max_legal_speed_kmh = float(max_legal_speed_kmh)

    def _heuristic(self, node_index: int, target_index: int, policy: EdgeCostPolicy) -> float:
        a = self.graph.nodes[node_index]
        b = self.graph.nodes[target_index]
        distance_m = geodesic_distance_m((a.lon, a.lat), (b.lon, b.lat))
        if policy.preference == RoutingPreference.SHORTEST:
            return distance_m
        max_speed_mps = self.max_legal_speed_kmh / 3.6
        return distance_m / max_speed_mps
