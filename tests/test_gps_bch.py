"""Automatic tests for the compact mmap-backed BCH1 routing sidecar."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from gps_bch import PersistentCHRouter, write_bch
from gps_ch import build_ch
from gps_routing import EdgeCostPolicy, GraphRouter, RoutingPreference
from routing_graph import RoutingProfile, WayInput, build_graph


def way(way_id: int, node_ids: list[int], coords: list[tuple[float, float]], **tags: str) -> WayInput:
    return WayInput(way_id, node_ids, coords, tags)


class PersistentBCHTests(unittest.TestCase):
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

    def assert_roundtrip_matches_reference(self, policy: EdgeCostPolicy) -> None:
        reference = GraphRouter(self.graph, RoutingProfile.NORMAL)
        index = build_ch(self.graph, RoutingProfile.NORMAL, policy)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "routing.bch"
            stats = write_bch(index, path)
            self.assertEqual(stats["node_count"], len(self.graph.nodes))
            self.assertEqual(stats["edge_count"], len(index.edges))
            self.assertGreater(stats["output_bytes"], 0)

            with PersistentCHRouter(self.graph, RoutingProfile.NORMAL, path) as router:
                self.assertEqual(router.preference, policy.preference)
                for start in range(len(self.graph.nodes)):
                    for target in range(len(self.graph.nodes)):
                        expected = reference.route_nodes(start, target, policy)
                        actual = router.route_nodes(start, target, policy)
                        self.assertEqual(actual.success, expected.success, (start, target, policy.preference))
                        self.assertAlmostEqual(actual.cost, expected.cost, places=7)
                        self.assertAlmostEqual(actual.distance_m, expected.distance_m, places=4)
                        self.assertAlmostEqual(actual.travel_time_s, expected.travel_time_s, places=7)
                        self.assertEqual(
                            tuple(step.edge_index for step in actual.steps),
                            tuple(step.edge_index for step in expected.steps),
                            (start, target, policy.preference),
                        )

    def test_fastest_roundtrip_matches_reference(self) -> None:
        self.assert_roundtrip_matches_reference(EdgeCostPolicy(RoutingPreference.FASTEST))

    def test_shortest_roundtrip_matches_reference(self) -> None:
        self.assert_roundtrip_matches_reference(EdgeCostPolicy(RoutingPreference.SHORTEST))

    def test_avoidance_roundtrip_matches_reference(self) -> None:
        self.assert_roundtrip_matches_reference(EdgeCostPolicy(RoutingPreference.AVOID_SMALL_ROADS, avoid_penalty=4.0))
        self.assert_roundtrip_matches_reference(EdgeCostPolicy(RoutingPreference.AVOID_MAJOR_ROADS, avoid_penalty=4.0))

    def test_metric_mismatch_is_rejected_after_load(self) -> None:
        policy = EdgeCostPolicy(RoutingPreference.FASTEST)
        index = build_ch(self.graph, RoutingProfile.NORMAL, policy)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "routing.bch"
            write_bch(index, path)
            with PersistentCHRouter(self.graph, RoutingProfile.NORMAL, path) as router:
                with self.assertRaises(ValueError):
                    router.route_nodes(0, 1, EdgeCostPolicy(RoutingPreference.SHORTEST))

    def test_invalid_magic_is_rejected(self) -> None:
        policy = EdgeCostPolicy(RoutingPreference.FASTEST)
        index = build_ch(self.graph, RoutingProfile.NORMAL, policy)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "routing.bch"
            write_bch(index, path)
            data = bytearray(path.read_bytes())
            data[:4] = b"NOPE"
            path.write_bytes(data)
            with self.assertRaises(ValueError):
                PersistentCHRouter(self.graph, RoutingProfile.NORMAL, path)


if __name__ == "__main__":
    unittest.main()
