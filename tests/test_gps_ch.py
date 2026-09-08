"""Automatic tests for exact contraction-hierarchy GPS routing."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from gps_ch import CHGraphRouter, build_ch
from gps_routing import EdgeCostPolicy, GraphRouter, RoutingPreference
from routing_graph import RoutingProfile, WayInput, build_graph


def way(way_id: int, node_ids: list[int], coords: list[tuple[float, float]], **tags: str) -> WayInput:
    return WayInput(way_id, node_ids, coords, tags)


def node_index(graph, osm_id: int) -> int:
    return next(index for index, node in enumerate(graph.nodes) if node.osm_id == osm_id)


class ContractionHierarchyTests(unittest.TestCase):
    def setUp(self) -> None:
        a = (13.0000, 55.0000)
        b = (13.0010, 55.0010)
        c = (13.0020, 55.0010)
        d = (13.0030, 55.0000)
        e = (13.0015, 54.9992)
        self.graph, _ = build_graph(
            [
                way(10, [1, 2, 3, 4], [a, b, c, d], highway="primary", maxspeed="90"),
                way(20, [1, 5, 4], [a, e, d], highway="residential", maxspeed="30"),
                way(30, [2, 5], [b, e], highway="secondary", maxspeed="50", oneway="yes"),
            ]
        )

    def assert_matches_reference(self, policy: EdgeCostPolicy) -> None:
        reference = GraphRouter(self.graph, RoutingProfile.NORMAL)
        index = build_ch(self.graph, RoutingProfile.NORMAL, policy)
        router = CHGraphRouter(self.graph, RoutingProfile.NORMAL, index)
        for start in range(len(self.graph.nodes)):
            for target in range(len(self.graph.nodes)):
                expected = reference.route_nodes(start, target, policy)
                actual = router.route_nodes(start, target, policy)
                self.assertEqual(actual.success, expected.success, (start, target, policy.preference))
                self.assertAlmostEqual(actual.cost, expected.cost, places=7)
                self.assertAlmostEqual(actual.distance_m, expected.distance_m, places=4)

    def test_fastest_matches_reference_for_all_node_pairs(self) -> None:
        self.assert_matches_reference(EdgeCostPolicy(RoutingPreference.FASTEST))

    def test_shortest_matches_reference_for_all_node_pairs(self) -> None:
        self.assert_matches_reference(EdgeCostPolicy(RoutingPreference.SHORTEST))

    def test_avoidance_metrics_match_reference(self) -> None:
        self.assert_matches_reference(EdgeCostPolicy(RoutingPreference.AVOID_SMALL_ROADS, avoid_penalty=4.0))
        self.assert_matches_reference(EdgeCostPolicy(RoutingPreference.AVOID_MAJOR_ROADS, avoid_penalty=4.0))

    def test_shortcuts_unpack_to_original_brg_edges(self) -> None:
        policy = EdgeCostPolicy(RoutingPreference.FASTEST)
        index = build_ch(self.graph, RoutingProfile.NORMAL, policy)
        self.assertTrue(any(edge.shortcut for edge in index.edges))
        router = CHGraphRouter(self.graph, RoutingProfile.NORMAL, index)
        result = router.route_nodes(node_index(self.graph, 1), node_index(self.graph, 4), policy)
        self.assertTrue(result.success)
        self.assertTrue(result.steps)
        for step in result.steps:
            self.assertGreaterEqual(step.edge_index, 0)
            self.assertLess(step.edge_index, len(self.graph.edges))

    def test_metric_mismatch_is_rejected(self) -> None:
        fastest = EdgeCostPolicy(RoutingPreference.FASTEST)
        index = build_ch(self.graph, RoutingProfile.NORMAL, fastest)
        router = CHGraphRouter(self.graph, RoutingProfile.NORMAL, index)
        with self.assertRaises(ValueError):
            router.route_nodes(0, 1, EdgeCostPolicy(RoutingPreference.SHORTEST))

    def test_normal_profile_keeps_oneway_legality(self) -> None:
        graph, _ = build_graph(
            [way(99, [1, 2, 3], [(13.0, 55.0), (13.001, 55.0), (13.002, 55.0)], highway="primary", oneway="yes")]
        )
        policy = EdgeCostPolicy(RoutingPreference.FASTEST)
        router = CHGraphRouter(graph, RoutingProfile.NORMAL, build_ch(graph, RoutingProfile.NORMAL, policy))
        forward = router.route_nodes(node_index(graph, 1), node_index(graph, 3), policy)
        reverse = router.route_nodes(node_index(graph, 3), node_index(graph, 1), policy)
        self.assertTrue(forward.success)
        self.assertFalse(reverse.success)


if __name__ == "__main__":
    unittest.main()
