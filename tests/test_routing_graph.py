"""Automatic correctness tests for BRG1 routing graph construction."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from build_routing import build_routing
from routing_graph import (
    AccessClass,
    AccessReason,
    FLAG_BRIDGE,
    FLAG_TUNNEL,
    RoutingProfile,
    SpeedSource,
    WayInput,
    build_graph,
    classify_access,
    is_edge_allowed,
    load_brg1,
    parse_maxspeed,
    parse_oneway,
    write_brg1,
)


def way(way_id: int, node_ids: list[int], coords: list[tuple[float, float]], **tags: str) -> WayInput:
    return WayInput(way_id, node_ids, coords, tags)


class RoutingPolicyTests(unittest.TestCase):
    def test_speed_parsing_and_fallback(self) -> None:
        self.assertEqual(parse_maxspeed("70", "primary").kmh, 70.0)
        self.assertAlmostEqual(parse_maxspeed("50 mph", "primary").kmh, 80.4672, places=4)
        bad = parse_maxspeed("signals", "residential")
        self.assertEqual(bad.source, SpeedSource.FALLBACK)
        self.assertEqual(bad.unknown_raw, "signals")
        self.assertEqual(parse_maxspeed(None, "residential").kmh, 40.0)

    def test_directional_speeds_are_preserved_per_edge(self) -> None:
        graph, _ = build_graph(
            [way(99, [90, 91], [(13.0, 55.0), (13.001, 55.0)], highway="primary", **{"maxspeed:forward": "80", "maxspeed:backward": "60"})]
        )
        by_source = {graph.nodes[edge.source_index].osm_id: edge.speed_kmh for edge in graph.edges}
        self.assertEqual(by_source[90], 80.0)
        self.assertEqual(by_source[91], 60.0)

    def test_oneway_variants_and_roundabout(self) -> None:
        self.assertEqual(parse_oneway({"oneway": "yes"}), 1)
        self.assertEqual(parse_oneway({"oneway": "1"}), 1)
        self.assertEqual(parse_oneway({"oneway": "true"}), 1)
        self.assertEqual(parse_oneway({"oneway": "-1"}), -1)
        self.assertEqual(parse_oneway({"junction": "roundabout"}), 1)
        self.assertEqual(parse_oneway({"junction": "roundabout", "oneway": "no"}), 0)

    def test_access_policy(self) -> None:
        self.assertEqual(classify_access("residential", {}).access_class, AccessClass.NORMAL)
        self.assertEqual(classify_access("service", {"access": "destination"}).access_class, AccessClass.DESTINATION)
        self.assertEqual(classify_access("service", {"access": "private"}).access_class, AccessClass.FORBIDDEN_NORMAL)
        self.assertEqual(classify_access("residential", {"motor_vehicle": "no"}).reason, AccessReason.MOTOR_VEHICLE_NO)
        self.assertEqual(classify_access("cycleway", {}).reason, AccessReason.NON_CAR_HIGHWAY)
        self.assertEqual(classify_access("cycleway", {"motor_vehicle": "yes"}).access_class, AccessClass.NORMAL)


class GraphConstructionTests(unittest.TestCase):
    def test_two_way_and_oneway_profile_behavior(self) -> None:
        graph, _ = build_graph(
            [way(1, [10, 11], [(13.0, 55.0), (13.001, 55.0)], highway="residential", oneway="yes", maxspeed="50")]
        )
        self.assertEqual(len(graph.edges), 2)
        legal = [edge for edge in graph.edges if not edge.against_oneway][0]
        reverse = [edge for edge in graph.edges if edge.against_oneway][0]
        self.assertTrue(is_edge_allowed(legal, RoutingProfile.NORMAL))
        self.assertFalse(is_edge_allowed(reverse, RoutingProfile.NORMAL))
        self.assertTrue(is_edge_allowed(reverse, RoutingProfile.PURSUIT))
        self.assertTrue(is_edge_allowed(reverse, RoutingProfile.GETAWAY))

    def test_reverse_oneway_marks_forward_direction_illegal(self) -> None:
        graph, _ = build_graph(
            [way(2, [20, 21], [(13.0, 55.0), (13.001, 55.0)], highway="service", oneway="-1")]
        )
        edge_20_to_21 = next(edge for edge in graph.edges if graph.nodes[edge.source_index].osm_id == 20)
        self.assertTrue(edge_20_to_21.against_oneway)

    def test_cycleway_is_kept_but_blocked_for_normal(self) -> None:
        graph, _ = build_graph([way(3, [30, 31], [(13.0, 55.0), (13.001, 55.0)], highway="cycleway")])
        self.assertEqual(len(graph.edges), 2)
        self.assertTrue(all(edge.access_class == AccessClass.FORBIDDEN_NORMAL for edge in graph.edges))
        self.assertFalse(is_edge_allowed(graph.edges[0], RoutingProfile.NORMAL))
        self.assertTrue(is_edge_allowed(graph.edges[0], RoutingProfile.GETAWAY))

    def test_bridge_and_tunnel_metadata_survive_without_geometric_connections(self) -> None:
        ways = [
            way(10, [1, 2], [(13.0, 55.0), (13.002, 55.002)], highway="primary"),
            way(11, [3, 4], [(13.0, 55.002), (13.002, 55.0)], highway="secondary", bridge="yes", layer="1"),
            way(12, [5, 6], [(13.0, 55.001), (13.002, 55.001)], highway="tertiary", tunnel="yes", layer="-1"),
        ]
        graph, _ = build_graph(ways)
        self.assertEqual(len(graph.nodes), 6)
        bridge_edges = [edge for edge in graph.edges if edge.way_id == 11]
        tunnel_edges = [edge for edge in graph.edges if edge.way_id == 12]
        self.assertTrue(all(edge.flags & FLAG_BRIDGE for edge in bridge_edges))
        self.assertTrue(all(edge.layer == 1 for edge in bridge_edges))
        self.assertTrue(all(edge.flags & FLAG_TUNNEL for edge in tunnel_edges))
        self.assertTrue(all(edge.layer == -1 for edge in tunnel_edges))

    def test_shared_osm_node_creates_real_junction(self) -> None:
        graph, _ = build_graph(
            [
                way(20, [1, 2, 3], [(13.0, 55.0), (13.001, 55.0), (13.002, 55.0)], highway="residential"),
                way(21, [4, 2, 5], [(13.001, 54.999), (13.001, 55.0), (13.001, 55.001)], highway="service"),
            ]
        )
        node2_index = next(i for i, node in enumerate(graph.nodes) if node.osm_id == 2)
        outgoing = graph.edges[
            graph.nodes[node2_index].adjacency_offset : graph.nodes[node2_index].adjacency_offset + graph.nodes[node2_index].adjacency_count
        ]
        self.assertEqual(len(outgoing), 4)

    def test_geodesic_length_is_not_mercator_planar_truth(self) -> None:
        graph, _ = build_graph([way(22, [1, 2], [(13.0, 60.0), (13.01, 60.0)], highway="primary")])
        self.assertGreater(graph.edges[0].length_m, 500.0)
        self.assertLess(graph.edges[0].length_m, 600.0)

    def test_stats_cover_fallback_unknown_and_restrictions(self) -> None:
        graph, stats = build_graph(
            [way(30, [1, 2], [(13.0, 55.0), (13.001, 55.0)], highway="cycleway", maxspeed="signals", oneway="yes")]
        )
        self.assertEqual(len(graph.edges), 2)
        self.assertEqual(stats.fallback_speed_edges, 2)
        self.assertEqual(stats.fallback_by_highway["cycleway"], 2)
        self.assertEqual(stats.unknown_maxspeed["signals"], 2)
        self.assertEqual(stats.restricted_edges, 2)
        self.assertEqual(stats.against_oneway_edges, 1)

    def test_stable_edge_ids_are_independent_of_way_iteration_order(self) -> None:
        inputs = [
            way(40, [10, 11], [(13.0, 55.0), (13.001, 55.0)], highway="residential"),
            way(41, [11, 12], [(13.001, 55.0), (13.002, 55.0)], highway="primary"),
        ]
        graph_a, _ = build_graph(inputs)
        graph_b, _ = build_graph(reversed(inputs))
        ids_a = [graph_a.stable_edge_id(edge) for edge in graph_a.edges]
        ids_b = [graph_b.stable_edge_id(edge) for edge in graph_b.edges]
        self.assertEqual(ids_a, ids_b)

    def test_brg1_round_trip(self) -> None:
        graph, _ = build_graph(
            [way(50, [1, 2], [(13.0, 55.0), (13.001, 55.0)], highway="primary", maxspeed="70", bridge="yes")]
        )
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "routing.brg"
            write_brg1(graph, path)
            loaded = load_brg1(path)
        self.assertEqual(len(graph.nodes), len(loaded.nodes))
        self.assertEqual(len(graph.edges), len(loaded.edges))
        self.assertEqual([graph.stable_edge_id(e) for e in graph.edges], [loaded.stable_edge_id(e) for e in loaded.edges])
        self.assertEqual([e.flags for e in graph.edges], [e.flags for e in loaded.edges])


class EndToEndBuildTests(unittest.TestCase):
    def test_osm_fixture_to_brg1_to_loader(self) -> None:
        fixture = ROOT / "tests" / "fixtures" / "routing_minimal.osm"
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp)
            report = build_routing(fixture, output)
            graph = load_brg1(output / "routing.brg")
            disk_report = json.loads((output / "routing_stats.json").read_text(encoding="utf-8"))

        self.assertEqual(report["format"], "BRG1")
        self.assertEqual(report, disk_report)
        self.assertGreater(len(graph.nodes), 0)
        self.assertGreater(len(graph.edges), 0)
        self.assertEqual(report["unknown_maxspeed"], {"signals": 2})
        self.assertEqual(sum(1 for edge in graph.edges if edge.against_oneway), 2)
        self.assertTrue(any(edge.bridge and edge.layer == 1 for edge in graph.edges))

    def test_interrupted_write_preserves_existing_graph(self) -> None:
        fixture = ROOT / "tests" / "fixtures" / "routing_minimal.osm"
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp)
            graph_path = output / "routing.brg"
            graph_path.write_bytes(b"known-good-routing")

            with patch("build_routing.write_brg1", side_effect=KeyboardInterrupt):
                with self.assertRaises(KeyboardInterrupt):
                    build_routing(fixture, output)

            self.assertEqual(graph_path.read_bytes(), b"known-good-routing")
            self.assertFalse((output / "routing.brg.tmp").exists())


if __name__ == "__main__":
    unittest.main()
