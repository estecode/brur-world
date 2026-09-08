"""Automatic tests for the large-graph A* GPS specialization."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from gps_astar import AStarGraphRouter
from gps_routing import EdgeCostPolicy, GraphRouter, RoutingPreference
from gps_snap_index import PersistentRoadSnapIndex, build_snap_index
from routing_graph import RoutingProfile, WayInput, build_graph, write_brg1
from routing_graph_view import RoutingGraphView


def way(way_id: int, node_ids: list[int], coords: list[tuple[float, float]], **tags: str) -> WayInput:
    return WayInput(way_id, node_ids, coords, tags)


def node_index(graph, osm_id: int) -> int:
    return next(index for index, node in enumerate(graph.nodes) if node.osm_id == osm_id)


class AStarGpsTests(unittest.TestCase):
    def test_astar_matches_baseline_router_for_all_preferences(self) -> None:
        graph, _ = build_graph(
            [
                way(10, [1, 2, 4], [(13.0, 55.0), (13.001, 55.001), (13.003, 55.0)], highway="primary", maxspeed="100"),
                way(20, [1, 3, 4], [(13.0, 55.0), (13.0015, 55.0), (13.003, 55.0)], highway="residential", maxspeed="40"),
            ]
        )
        start = node_index(graph, 1)
        target = node_index(graph, 4)
        baseline = GraphRouter(graph, RoutingProfile.NORMAL)
        astar = AStarGraphRouter(graph, RoutingProfile.NORMAL, 100.0)
        for preference in RoutingPreference:
            policy = EdgeCostPolicy(preference)
            self.assertEqual(
                astar.route_nodes(start, target, policy),
                baseline.route_nodes(start, target, policy),
            )

    def test_snapped_astar_matches_baseline_and_uses_one_search(self) -> None:
        graph, _ = build_graph(
            [
                way(10, [1, 2, 4], [(13.0, 55.0), (13.001, 55.001), (13.003, 55.0)], highway="primary", maxspeed="100"),
                way(20, [1, 3, 4], [(13.0, 55.0), (13.0015, 55.0), (13.003, 55.0)], highway="residential", maxspeed="40"),
            ]
        )
        with tempfile.TemporaryDirectory() as temp:
            graph_path = Path(temp) / "routing.brg"
            snap_path = Path(temp) / "routing_snap.brs"
            write_brg1(graph, graph_path)
            with RoutingGraphView(graph_path) as view:
                build_snap_index(view, snap_path, cell_size_m=100.0)
                with PersistentRoadSnapIndex(view, snap_path, RoutingProfile.NORMAL) as snap_index:
                    edge_a = view.edges[0]
                    edge_b = view.edges[len(view.edges) - 1]
                    a0 = view.nodes[edge_a.source_index]
                    a1 = view.nodes[edge_a.target_index]
                    b0 = view.nodes[edge_b.source_index]
                    b1 = view.nodes[edge_b.target_index]
                    start = snap_index.snap((a0.x + a1.x) * 0.5, (a0.y + a1.y) * 0.5, 100.0)
                    target = snap_index.snap((b0.x + b1.x) * 0.5, (b0.y + b1.y) * 0.5, 100.0)
                    self.assertIsNotNone(start)
                    self.assertIsNotNone(target)
                    baseline = GraphRouter(view, RoutingProfile.NORMAL)
                    astar = AStarGraphRouter(view, RoutingProfile.NORMAL, snap_index.max_legal_speed_kmh)
                    for preference in RoutingPreference:
                        policy = EdgeCostPolicy(preference)
                        self.assertEqual(astar.route_snaps(start, target, policy), baseline.route_snaps(start, target, policy))
                        self.assertEqual(astar.last_stats["searches"], 1)

    def test_brs2_stores_maximum_normal_profile_speed(self) -> None:
        graph, _ = build_graph(
            [
                way(10, [1, 2], [(13.0, 55.0), (13.001, 55.0)], highway="primary", maxspeed="120"),
                way(20, [2, 3], [(13.001, 55.0), (13.002, 55.0)], highway="cycleway", maxspeed="250"),
            ]
        )
        with tempfile.TemporaryDirectory() as temp:
            graph_path = Path(temp) / "routing.brg"
            snap_path = Path(temp) / "routing_snap.brs"
            write_brg1(graph, graph_path)
            with RoutingGraphView(graph_path) as view:
                report = build_snap_index(view, snap_path, cell_size_m=100.0)
                self.assertAlmostEqual(float(report["max_legal_speed_kmh"]), 120.0, places=4)
                with PersistentRoadSnapIndex(view, snap_path, RoutingProfile.NORMAL) as snap_index:
                    self.assertAlmostEqual(snap_index.max_legal_speed_kmh, 120.0, places=4)


if __name__ == "__main__":
    unittest.main()
