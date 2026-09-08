"""Automatic tests for exact bidirectional GPS routing and BRI1 reverse adjacency."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from gps_bidirectional import BidirectionalGraphRouter
from gps_incoming_index import IncomingEdgeIndex, build_incoming_index
from gps_routing import EdgeCostPolicy, GraphRouter, RoutingPreference
from routing_graph import RoutingProfile, WayInput, build_graph, write_brg1
from routing_graph_view import RoutingGraphView


def _node_index(graph, osm_id: int) -> int:
    return next(index for index, node in enumerate(graph.nodes) if node.osm_id == osm_id)


class BidirectionalRoutingTests(unittest.TestCase):
    def _with_router(self, graph, callback) -> None:
        with tempfile.TemporaryDirectory() as temp:
            graph_path = Path(temp) / "routing.brg"
            incoming_path = Path(temp) / "routing_incoming.bri"
            write_brg1(graph, graph_path)
            with RoutingGraphView(graph_path) as view:
                build_incoming_index(view, incoming_path)
                with IncomingEdgeIndex(incoming_path, len(view.nodes), len(view.edges)) as incoming:
                    callback(view, BidirectionalGraphRouter(view, RoutingProfile.NORMAL, incoming))

    def test_matches_forward_router_for_all_preferences(self) -> None:
        graph, _ = build_graph(
            [
                WayInput(10, [1, 2, 4], [(13.0, 55.0), (13.001, 55.001), (13.003, 55.0)], {"highway": "primary", "maxspeed": "90"}),
                WayInput(20, [1, 3, 4], [(13.0, 55.0), (13.0015, 55.0), (13.003, 55.0)], {"highway": "residential", "maxspeed": "40"}),
            ]
        )

        def check(view, bidirectional):
            baseline = GraphRouter(view, RoutingProfile.NORMAL)
            start = _node_index(view, 1)
            target = _node_index(view, 4)
            for preference in RoutingPreference:
                policy = EdgeCostPolicy(preference)
                expected = baseline.route_nodes(start, target, policy)
                actual = bidirectional.route_nodes(start, target, policy)
                self.assertEqual(actual.success, expected.success)
                self.assertAlmostEqual(actual.cost, expected.cost, places=6)
                self.assertAlmostEqual(actual.distance_m, expected.distance_m, places=4)
                self.assertAlmostEqual(actual.travel_time_s, expected.travel_time_s, places=4)

        self._with_router(graph, check)

    def test_obeys_oneway_and_reports_unreachable(self) -> None:
        graph, _ = build_graph(
            [WayInput(10, [1, 2, 3], [(13.0, 55.0), (13.001, 55.0), (13.002, 55.0)], {"highway": "primary", "oneway": "yes"})]
        )

        def check(view, router):
            forward = router.route_nodes(_node_index(view, 1), _node_index(view, 3), EdgeCostPolicy())
            reverse = router.route_nodes(_node_index(view, 3), _node_index(view, 1), EdgeCostPolicy())
            self.assertTrue(forward.success)
            self.assertFalse(reverse.success)
            self.assertEqual(reverse.failure_reason, "unreachable")

        self._with_router(graph, check)

    def test_incoming_index_rejects_wrong_graph_counts(self) -> None:
        graph, _ = build_graph(
            [WayInput(1, [1, 2], [(13.0, 55.0), (13.001, 55.0)], {"highway": "residential"})]
        )
        with tempfile.TemporaryDirectory() as temp:
            graph_path = Path(temp) / "routing.brg"
            incoming_path = Path(temp) / "routing_incoming.bri"
            write_brg1(graph, graph_path)
            with RoutingGraphView(graph_path) as view:
                build_incoming_index(view, incoming_path)
            with self.assertRaises(ValueError):
                IncomingEdgeIndex(incoming_path, expected_node_count=999)


if __name__ == "__main__":
    unittest.main()
