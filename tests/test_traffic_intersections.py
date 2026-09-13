"""Tests deterministic traffic-intersection movements, stops, grouping and conflicts.

Dependencies:
- Uses production traffic_intersections and routing_graph domain modules.
- Uses only tiny deterministic routing/signal fixtures; no Godot or PBF input.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from routing_graph import WayInput, build_graph
from traffic_intersections import Approach, Exit, StopPosition, build_from_runtime_data, build_intersection, derive_stop_position


def approach(name: str, x: float, y: float, *, resolved: bool = True) -> Approach:
    return Approach(name, name, int(name.split(":")[-1]), (), x, y, "explicit", "explicit" if resolved else "unresolved", StopPosition(x, y, "explicit"), resolved)


def exit_row(name: str, osm: int, way: int, x: float, y: float) -> Exit:
    return Exit(name, osm, way, x, y)


class TrafficIntersectionTests(unittest.TestCase):
    def test_explicit_stop_wins_and_fallback_is_derived(self) -> None:
        explicit = derive_stop_position((0.0, -20.0), (0.0, 0.0), explicit_xy=(1.0, -7.0))
        self.assertEqual(explicit, StopPosition(1.0, -7.0, "explicit"))
        derived = derive_stop_position((0.0, -20.0), (0.0, 0.0), setback_m=4.0)
        self.assertEqual(derived.source, "derived")
        self.assertAlmostEqual(derived.x, 0.0)
        self.assertAlmostEqual(derived.y, -4.0)

    def test_four_way_crossing_conflicts_but_opposing_straights_do_not(self) -> None:
        item = build_intersection(
            "cross", 1, (0.0, 0.0),
            [approach("a:1", 0.0, -10.0), approach("a:2", 0.0, 10.0), approach("a:3", -10.0, 0.0), approach("a:4", 10.0, 0.0)],
            [exit_row("e:north", 11, 101, 0.0, -10.0), exit_row("e:south", 12, 102, 0.0, 10.0), exit_row("e:west", 13, 103, -10.0, 0.0), exit_row("e:east", 14, 104, 10.0, 0.0)],
        )
        self.assertFalse(item.conflicts_with("a:1->e:south", "a:2->e:north"))
        self.assertTrue(item.conflicts_with("a:1->e:south", "a:3->e:east"))

    def test_same_approach_conflicts_and_unknown_is_conservative(self) -> None:
        item = build_intersection(
            "t", 1, (0.0, 0.0),
            [approach("a:1", 0.0, -10.0), approach("a:2", -10.0, 0.0, resolved=False)],
            [exit_row("e:north", 11, 101, 0.0, -10.0), exit_row("e:east", 12, 102, 10.0, 0.0), exit_row("e:west", 13, 103, -10.0, 0.0)],
        )
        rows = {movement.id: movement for movement in item.movements}
        same_approach = sorted(mid for mid in rows if mid.startswith("a:1->"))
        self.assertGreaterEqual(len(same_approach), 2)
        self.assertTrue(item.conflicts_with(same_approach[0], same_approach[1]))
        unresolved = [mid for mid, movement in rows.items() if not movement.resolved]
        self.assertTrue(unresolved)
        for mid in unresolved:
            for other in rows:
                if mid != other:
                    self.assertTrue(item.conflicts_with(mid, other))

    def test_runtime_adapter_groups_signal_to_authoritative_routing_junction(self) -> None:
        ways = [
            WayInput(101, [1, 2, 3], [(18.0, 59.0), (18.0001, 59.0), (18.0002, 59.0)], {"highway": "primary"}),
            WayInput(102, [4, 2, 5], [(18.0001, 58.9999), (18.0001, 59.0), (18.0001, 59.0001)], {"highway": "secondary"}),
        ]
        graph, _ = build_graph(ways)
        node = next(node for node in graph.nodes if node.osm_id == 1)
        dataset = {"format": "BTS1", "signals": [{"id": "n1", "osm_node_id": 1, "x": node.x, "y": node.y, "highway_way_ids": [101], "direction_source": "explicit", "explicit_stop_line": True}]}
        report = build_from_runtime_data(dataset, graph)
        self.assertEqual(report.unresolved_signal_ids, ())
        self.assertEqual(len(report.intersections), 1)
        intersection = report.intersections[0]
        self.assertEqual(intersection.junction_osm_node_id, 2)
        self.assertEqual(intersection.approaches[0].relationship_source, "explicit")
        self.assertEqual(intersection.approaches[0].stop.source, "explicit")
        self.assertGreaterEqual(len(intersection.movements), 2)
        self.assertEqual(intersection, build_from_runtime_data(dataset, graph).intersections[0])

    def test_unknown_single_way_relationship_is_inferred_without_rewriting_source(self) -> None:
        graph, _ = build_graph([
            WayInput(101, [1, 2, 3], [(18.0, 59.0), (18.0001, 59.0), (18.0002, 59.0)], {"highway": "primary"}),
            WayInput(102, [4, 2], [(18.0001, 58.9999), (18.0001, 59.0)], {"highway": "secondary"}),
        ])
        node = next(node for node in graph.nodes if node.osm_id == 1)
        dataset = {"format": "BTS1", "signals": [{"id": "n1", "osm_node_id": 1, "x": node.x, "y": node.y, "highway_way_ids": [101], "direction_source": "unknown", "explicit_stop_line": False}]}
        row = build_from_runtime_data(dataset, graph).intersections[0].approaches[0]
        self.assertEqual(row.direction_source, "unknown")
        self.assertEqual(row.relationship_source, "inferred")
        self.assertTrue(row.resolved)

    def test_one_way_and_restricted_exits_follow_normal_routing_policy(self) -> None:
        graph, _ = build_graph([
            WayInput(101, [1, 2], [(18.0, 59.0), (18.0001, 59.0)], {"highway": "primary"}),
            WayInput(102, [2, 3], [(18.0001, 59.0), (18.0002, 59.0)], {"highway": "primary", "oneway": "yes"}),
            WayInput(103, [2, 4], [(18.0001, 59.0), (18.0001, 59.0001)], {"highway": "service", "access": "customers"}),
        ])
        signal = next(node for node in graph.nodes if node.osm_id == 1)
        dataset = {"format": "BTS1", "signals": [{"id": "n1", "osm_node_id": 1, "x": signal.x, "y": signal.y, "highway_way_ids": [101], "direction_source": "explicit", "explicit_stop_line": False}]}
        exits = {(row.way_id, row.node_osm_id) for row in build_from_runtime_data(dataset, graph).intersections[0].exits}
        self.assertIn((102, 3), exits)
        self.assertNotIn((103, 4), exits)

    def test_missing_signal_topology_remains_unresolved(self) -> None:
        graph, _ = build_graph([WayInput(101, [1, 2], [(18.0, 59.0), (18.0001, 59.0)], {"highway": "primary"})])
        dataset = {"format": "BTS1", "signals": [{"id": "missing", "osm_node_id": 999, "highway_way_ids": [101]}]}
        report = build_from_runtime_data(dataset, graph)
        self.assertEqual(report.intersections, ())
        self.assertEqual(report.unresolved_signal_ids, ("missing",))


if __name__ == "__main__":
    unittest.main()
