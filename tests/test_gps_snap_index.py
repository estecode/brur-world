"""Automatic tests for the persistent BRS1 GPS road-snap index."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from gps_routing import RoadSnapIndex
from gps_snap_index import PersistentRoadSnapIndex, build_snap_index
from routing_graph import RoutingProfile, WayInput, build_graph, write_brg1
from routing_graph_view import RoutingGraphView


class PersistentSnapIndexTests(unittest.TestCase):
    def test_persistent_index_matches_in_memory_snap(self) -> None:
        graph, _ = build_graph(
            [
                WayInput(1, [10, 11], [(13.0, 55.0), (13.001, 55.0)], {"highway": "residential"}),
                WayInput(2, [11, 12], [(13.001, 55.0), (13.002, 55.001)], {"highway": "primary", "oneway": "yes"}),
            ]
        )
        with tempfile.TemporaryDirectory() as temp:
            graph_path = Path(temp) / "routing.brg"
            snap_path = Path(temp) / "routing_snap.brs"
            write_brg1(graph, graph_path)
            with RoutingGraphView(graph_path) as view:
                expected_index = RoadSnapIndex(view, RoutingProfile.NORMAL, cell_size_m=100.0)
                build_snap_index(view, snap_path, cell_size_m=100.0)
                with PersistentRoadSnapIndex(view, snap_path, RoutingProfile.NORMAL) as actual_index:
                    node = view.nodes[1]
                    expected = expected_index.snap(node.x + 5.0, node.y + 2.0, 50.0)
                    actual = actual_index.snap(node.x + 5.0, node.y + 2.0, 50.0)
                    self.assertIsNotNone(expected)
                    self.assertIsNotNone(actual)
                    self.assertAlmostEqual(actual.x, expected.x, places=4)
                    self.assertAlmostEqual(actual.y, expected.y, places=4)
                    self.assertAlmostEqual(actual.distance_m, expected.distance_m, places=4)
                    self.assertEqual(actual.directions, expected.directions)

    def test_bad_snap_index_file_is_rejected(self) -> None:
        graph, _ = build_graph(
            [WayInput(1, [10, 11], [(13.0, 55.0), (13.001, 55.0)], {"highway": "residential"})]
        )
        with tempfile.TemporaryDirectory() as temp:
            graph_path = Path(temp) / "routing.brg"
            snap_path = Path(temp) / "routing_snap.brs"
            write_brg1(graph, graph_path)
            snap_path.write_bytes(b"BRS1")
            with RoutingGraphView(graph_path) as view:
                with self.assertRaises(ValueError):
                    PersistentRoadSnapIndex(view, snap_path)


if __name__ == "__main__":
    unittest.main()
