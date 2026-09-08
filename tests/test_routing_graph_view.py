"""Automatic tests for the lazy BRG1 runtime view used by GPS routing."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from gps_routing import EdgeCostPolicy, GraphRouter, RoadSnapIndex, RoutingPreference
from routing_graph import RoutingProfile, WayInput, build_graph, load_brg1, write_brg1
from routing_graph_view import RoutingGraphView


class RoutingGraphViewTests(unittest.TestCase):
    def test_lazy_view_matches_brg1_records_and_routes(self) -> None:
        graph, _ = build_graph(
            [
                WayInput(1, [10, 11], [(13.0, 55.0), (13.001, 55.0)], {"highway": "residential", "maxspeed": "40"}),
                WayInput(2, [11, 12], [(13.001, 55.0), (13.002, 55.0)], {"highway": "primary", "maxspeed": "70"}),
            ]
        )
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "routing.brg"
            write_brg1(graph, path)
            serialized = load_brg1(path)
            with RoutingGraphView(path) as view:
                self.assertEqual(len(view.nodes), len(serialized.nodes))
                self.assertEqual(len(view.edges), len(serialized.edges))
                self.assertEqual(view.nodes[1], serialized.nodes[1])
                self.assertEqual(view.edges[2], serialized.edges[2])

                snap_index = RoadSnapIndex(view, RoutingProfile.NORMAL, cell_size_m=100.0)
                start_node = view.nodes[0]
                target_node = view.nodes[-1]
                start = snap_index.snap(start_node.x, start_node.y, 20.0)
                target = snap_index.snap(target_node.x, target_node.y, 20.0)
                self.assertIsNotNone(start)
                self.assertIsNotNone(target)
                result = GraphRouter(view).route_snaps(
                    start,
                    target,
                    EdgeCostPolicy(RoutingPreference.FASTEST),
                )
                self.assertTrue(result.success)
                self.assertGreater(result.distance_m, 0.0)

    def test_bad_file_size_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "routing.brg"
            path.write_bytes(b"BRG1" + b"\x00" * 20)
            with self.assertRaises(ValueError):
                RoutingGraphView(path)


if __name__ == "__main__":
    unittest.main()
