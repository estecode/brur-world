"""Automatic tests for click-to-road GPS routing and waypoint planning."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from gps_plan import RoutePlan, RouteTarget
from gps_routing import EdgeCostPolicy, GraphRouter, RoadSnapIndex, RoutingPreference
from routing_graph import RoutingProfile, WayInput, build_graph


def way(way_id: int, node_ids: list[int], coords: list[tuple[float, float]], **tags: str) -> WayInput:
    return WayInput(way_id, node_ids, coords, tags)


def node_index(graph, osm_id: int) -> int:
    return next(index for index, node in enumerate(graph.nodes) if node.osm_id == osm_id)


def edge_way_ids(graph, result) -> list[int]:
    return [graph.edges[step.edge_index].way_id for step in result.steps]


class GpsRoutingTests(unittest.TestCase):
    def test_fastest_and_shortest_choose_different_routes(self) -> None:
        a = (13.0000, 55.0000)
        b = (13.0007, 55.0010)
        c = (13.0013, 55.0010)
        d = (13.0020, 55.0000)
        graph, _ = build_graph(
            [
                way(10, [1, 2, 3, 4], [a, b, c, d], highway="primary", maxspeed="100"),
                way(20, [1, 4], [a, d], highway="residential", maxspeed="20"),
            ]
        )
        router = GraphRouter(graph)
        start = node_index(graph, 1)
        target = node_index(graph, 4)

        fastest = router.route_nodes(start, target, EdgeCostPolicy(RoutingPreference.FASTEST))
        shortest = router.route_nodes(start, target, EdgeCostPolicy(RoutingPreference.SHORTEST))

        self.assertTrue(fastest.success)
        self.assertTrue(shortest.success)
        self.assertEqual(set(edge_way_ids(graph, fastest)), {10})
        self.assertEqual(set(edge_way_ids(graph, shortest)), {20})
        self.assertLess(shortest.distance_m, fastest.distance_m)
        self.assertLess(fastest.travel_time_s, shortest.travel_time_s)

    def test_avoid_small_roads_is_penalty_not_ban(self) -> None:
        a = (13.0000, 55.0000)
        b = (13.0010, 55.0010)
        d = (13.0020, 55.0000)
        graph, _ = build_graph(
            [
                way(10, [1, 2, 3], [a, b, d], highway="primary", maxspeed="60"),
                way(20, [1, 3], [a, d], highway="residential", maxspeed="60"),
            ]
        )
        router = GraphRouter(graph)
        start = node_index(graph, 1)
        target = node_index(graph, 3)

        ordinary = router.route_nodes(start, target, EdgeCostPolicy(RoutingPreference.FASTEST))
        avoiding = router.route_nodes(start, target, EdgeCostPolicy(RoutingPreference.AVOID_SMALL_ROADS, avoid_penalty=4.0))
        self.assertEqual(set(edge_way_ids(graph, ordinary)), {20})
        self.assertEqual(set(edge_way_ids(graph, avoiding)), {10})

        required_graph, _ = build_graph([way(30, [7, 8], [a, d], highway="residential", maxspeed="40")])
        required = GraphRouter(required_graph).route_nodes(
            node_index(required_graph, 7),
            node_index(required_graph, 8),
            EdgeCostPolicy(RoutingPreference.AVOID_SMALL_ROADS, avoid_penalty=100.0),
        )
        self.assertTrue(required.success)
        self.assertEqual(set(edge_way_ids(required_graph, required)), {30})

    def test_avoid_major_roads_prefers_small_road_alternative(self) -> None:
        a = (13.0000, 55.0000)
        b = (13.0010, 55.0010)
        d = (13.0020, 55.0000)
        graph, _ = build_graph(
            [
                way(10, [1, 3], [a, d], highway="primary", maxspeed="60"),
                way(20, [1, 2, 3], [a, b, d], highway="residential", maxspeed="60"),
            ]
        )
        result = GraphRouter(graph).route_nodes(
            node_index(graph, 1),
            node_index(graph, 3),
            EdgeCostPolicy(RoutingPreference.AVOID_MAJOR_ROADS, avoid_penalty=4.0),
        )
        self.assertTrue(result.success)
        self.assertEqual(set(edge_way_ids(graph, result)), {20})

    def test_normal_profile_obeys_oneway_and_unreachable_is_clean(self) -> None:
        graph, _ = build_graph(
            [way(10, [1, 2, 3], [(13.0, 55.0), (13.001, 55.0), (13.002, 55.0)], highway="primary", oneway="yes")]
        )
        router = GraphRouter(graph, RoutingProfile.NORMAL)
        forward = router.route_nodes(node_index(graph, 1), node_index(graph, 3), EdgeCostPolicy())
        reverse = router.route_nodes(node_index(graph, 3), node_index(graph, 1), EdgeCostPolicy())
        self.assertTrue(forward.success)
        self.assertFalse(reverse.success)
        self.assertEqual(reverse.failure_reason, "unreachable")

    def test_snap_to_road_and_route_partial_edge(self) -> None:
        graph, _ = build_graph(
            [way(10, [1, 2], [(13.0, 55.0), (13.002, 55.0)], highway="primary", oneway="yes", maxspeed="60")]
        )
        index = RoadSnapIndex(graph, cell_size_m=500.0)
        a = graph.nodes[node_index(graph, 1)]
        b = graph.nodes[node_index(graph, 2)]
        start = index.snap(a.x * 0.75 + b.x * 0.25, a.y * 0.75 + b.y * 0.25, 10.0)
        destination = index.snap(a.x * 0.25 + b.x * 0.75, a.y * 0.25 + b.y * 0.75, 10.0)
        self.assertIsNotNone(start)
        self.assertIsNotNone(destination)
        assert start is not None and destination is not None
        self.assertEqual(len(start.directions), 1)
        result = GraphRouter(graph).route_snaps(start, destination, EdgeCostPolicy())
        self.assertTrue(result.success)
        self.assertEqual(len(result.steps), 1)
        self.assertAlmostEqual(result.steps[0].fraction, 0.5, places=6)

    def test_snap_rejects_position_too_far_from_road(self) -> None:
        graph, _ = build_graph([way(10, [1, 2], [(13.0, 55.0), (13.001, 55.0)], highway="primary")])
        index = RoadSnapIndex(graph, cell_size_m=500.0)
        node = graph.nodes[0]
        self.assertIsNone(index.snap(node.x + 10_000.0, node.y + 10_000.0, 50.0))

    def test_repeated_route_is_deterministic(self) -> None:
        graph, _ = build_graph(
            [
                way(10, [1, 2, 4], [(13.0, 55.0), (13.001, 55.001), (13.002, 55.0)], highway="primary"),
                way(20, [1, 3, 4], [(13.0, 55.0), (13.001, 54.999), (13.002, 55.0)], highway="primary"),
            ]
        )
        router = GraphRouter(graph)
        args = (node_index(graph, 1), node_index(graph, 4), EdgeCostPolicy(RoutingPreference.SHORTEST))
        first = router.route_nodes(*args)
        second = router.route_nodes(*args)
        self.assertEqual(first, second)


class RoutePlanTests(unittest.TestCase):
    def setUp(self) -> None:
        self.graph, _ = build_graph(
            [way(10, [1, 2, 3, 4], [(13.0, 55.0), (13.001, 55.0), (13.002, 55.0), (13.003, 55.0)], highway="primary")]
        )
        self.snap_index = RoadSnapIndex(self.graph, cell_size_m=500.0)
        self.router = GraphRouter(self.graph)
        self.policy = EdgeCostPolicy()

    def snap_node(self, osm_id: int):
        node = self.graph.nodes[node_index(self.graph, osm_id)]
        snap = self.snap_index.snap(node.x, node.y, 5.0)
        self.assertIsNotNone(snap)
        return snap

    def test_multiple_waypoints_preserve_explicit_leg_order(self) -> None:
        plan = RoutePlan()
        plan.add_waypoint(RouteTarget("w1", "Waypoint 1", self.snap_node(2)))
        plan.add_waypoint(RouteTarget("w2", "Waypoint 2", self.snap_node(3)))
        plan.set_destination(RouteTarget("dest", "Destination", self.snap_node(4)))
        result = plan.recalculate(self.snap_node(1), self.router, self.policy)
        self.assertTrue(result.success)
        self.assertEqual([(leg.from_id, leg.to_id) for leg in result.legs], [("start", "w1"), ("w1", "w2"), ("w2", "dest")])

    def test_remove_first_middle_last_and_all_waypoints(self) -> None:
        plan = RoutePlan()
        for target_id, osm_id in (("a", 2), ("b", 3), ("c", 3)):
            plan.add_waypoint(RouteTarget(target_id, target_id, self.snap_node(osm_id)))
        plan.set_destination(RouteTarget("dest", "Destination", self.snap_node(4)))

        self.assertEqual([target.target_id for target in plan.waypoints], ["a", "b", "c"])
        plan.remove_waypoint(0)
        self.assertEqual([target.target_id for target in plan.waypoints], ["b", "c"])
        plan.remove_waypoint(0)
        self.assertEqual([target.target_id for target in plan.waypoints], ["c"])
        plan.remove_waypoint(0)
        result = plan.recalculate(self.snap_node(1), self.router, self.policy)
        self.assertTrue(result.success)
        self.assertEqual([(leg.from_id, leg.to_id) for leg in result.legs], [("start", "dest")])

    def test_unreachable_waypoint_identifies_failed_leg(self) -> None:
        disconnected_graph, _ = build_graph(
            [
                way(10, [1, 2], [(13.0, 55.0), (13.001, 55.0)], highway="primary"),
                way(20, [3, 4], [(14.0, 56.0), (14.001, 56.0)], highway="primary"),
            ]
        )
        index = RoadSnapIndex(disconnected_graph, cell_size_m=1000.0)
        router = GraphRouter(disconnected_graph)
        n1 = disconnected_graph.nodes[node_index(disconnected_graph, 1)]
        n3 = disconnected_graph.nodes[node_index(disconnected_graph, 3)]
        n4 = disconnected_graph.nodes[node_index(disconnected_graph, 4)]
        start = index.snap(n1.x, n1.y, 5.0)
        waypoint = index.snap(n3.x, n3.y, 5.0)
        destination = index.snap(n4.x, n4.y, 5.0)
        assert start is not None and waypoint is not None and destination is not None
        plan = RoutePlan()
        plan.add_waypoint(RouteTarget("bad", "Unreachable", waypoint))
        plan.set_destination(RouteTarget("dest", "Destination", destination))
        result = plan.recalculate(start, router, EdgeCostPolicy())
        self.assertFalse(result.success)
        self.assertEqual(result.failed_leg_index, 0)
        self.assertEqual(result.legs[0].to_id, "bad")


if __name__ == "__main__":
    unittest.main()
