"""Architecture regression tests for portable high-performance routing data."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from gps_snap_index import DEFAULT_CELL_SIZE_M, PersistentRoadSnapIndex, build_snap_index
from routing_graph import WayInput, build_graph, write_brg1
from routing_graph_view import RoutingGraphView


class RoutingRuntimeContractTests(unittest.TestCase):
    def test_default_snap_grid_is_sub_kilometre(self) -> None:
        self.assertLessEqual(DEFAULT_CELL_SIZE_M, 512.0)

    def test_persistent_snap_reports_candidate_count_without_changing_result(self) -> None:
        graph, _ = build_graph(
            [
                WayInput(1, [10, 11], [(13.0, 55.0), (13.001, 55.0)], {"highway": "residential"}),
                WayInput(2, [11, 12], [(13.001, 55.0), (13.002, 55.0)], {"highway": "primary"}),
            ]
        )
        with tempfile.TemporaryDirectory() as temp:
            graph_path = Path(temp) / "routing.brg"
            snap_path = Path(temp) / "routing_snap.brs"
            write_brg1(graph, graph_path)
            with RoutingGraphView(graph_path) as view:
                build_snap_index(view, snap_path, cell_size_m=128.0)
                with PersistentRoadSnapIndex(view, snap_path) as index:
                    node = view.nodes[1]
                    ordinary = index.snap(node.x, node.y, 20.0)
                    measured, candidates = index.snap_with_stats(node.x, node.y, 20.0)
                    self.assertEqual(measured, ordinary)
                    self.assertGreater(candidates, 0)


if __name__ == "__main__":
    unittest.main()
