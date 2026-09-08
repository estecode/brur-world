"""Compile the portable GPS core and compare it with the Python routing reference.

Dependencies:
- Requires a local C++20 compiler (CXX, clang++, or g++).
- Uses routing_graph/gps_routing/gps_snap_index fixture builders only.
- Does not require Sweden data, Godot, sockets, or network access.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from gps_routing import EdgeCostPolicy, GraphRouter, RoadSnapIndex, RoutingPreference
from gps_snap_index import build_snap_index
from routing_graph import WayInput, build_graph, load_brg1, write_brg1

CORE = ROOT / "native" / "gps_core.cpp"
CORE_TEST = ROOT / "tests" / "native" / "test_gps_core.cpp"
CLI = ROOT / "native" / "gps_route_cli.cpp"


def way(way_id: int, node_ids: list[int], coords: list[tuple[float, float]], **tags: str) -> WayInput:
    return WayInput(way_id, node_ids, coords, tags)


def node_index(graph, osm_id: int) -> int:
    return next(index for index, node in enumerate(graph.nodes) if node.osm_id == osm_id)


class NativeGpsCoreTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.compiler = os.environ.get("CXX") or shutil.which("clang++") or shutil.which("g++")

    def test_portable_cpp_contract(self) -> None:
        if not self.compiler:
            self.skipTest("no C++20 compiler available")
        with tempfile.TemporaryDirectory(prefix="brur-native-gps-core-") as temp_dir:
            binary = Path(temp_dir) / "test_gps_core"
            subprocess.run(
                [self.compiler, "-std=c++20", "-O2", "-Wall", "-Wextra", "-pedantic",
                 str(CORE), str(CORE_TEST), "-o", str(binary)],
                cwd=ROOT, check=True, capture_output=True, text=True,
            )
            completed = subprocess.run(
                [str(binary)], cwd=ROOT, check=True, capture_output=True, text=True,
            )
            self.assertEqual(completed.stdout.strip(), "native gps core tests: OK")

    def test_python_parity_for_preferences_path_metrics_and_legality(self) -> None:
        if not self.compiler:
            self.skipTest("no C++20 compiler available")
        with tempfile.TemporaryDirectory(prefix="brur-native-gps-parity-") as temp_dir:
            temp = Path(temp_dir)
            cli = temp / "brur-gps-route"
            subprocess.run(
                [self.compiler, "-std=c++20", "-O2", "-Wall", "-Wextra", "-pedantic",
                 str(CORE), str(CLI), "-o", str(cli)],
                cwd=ROOT, check=True, capture_output=True, text=True,
            )

            a = (13.0000, 55.0000)
            split = (13.0002, 55.0000)
            bend = (13.0010, 55.0010)
            merge = (13.0020, 55.0000)
            z = (13.0022, 55.0000)
            graph, _ = build_graph([
                way(1, [1, 2], [a, split], highway="tertiary", maxspeed="50"),
                way(10, [2, 3, 4], [split, bend, merge], highway="primary", maxspeed="100"),
                way(20, [2, 4], [split, merge], highway="residential", maxspeed="20"),
                way(30, [4, 5], [merge, z], highway="tertiary", maxspeed="50"),
            ])
            graph_path = temp / "routing.brg"
            snap_path = temp / "routing_snap.brs"
            write_brg1(graph, graph_path)
            graph = load_brg1(graph_path)
            build_snap_index(graph, snap_path, cell_size_m=500.0)

            start_a = graph.nodes[node_index(graph, 1)]
            start_b = graph.nodes[node_index(graph, 2)]
            target_a = graph.nodes[node_index(graph, 4)]
            target_b = graph.nodes[node_index(graph, 5)]
            start_xy = ((start_a.x + start_b.x) * 0.5, (start_a.y + start_b.y) * 0.5)
            target_xy = ((target_a.x + target_b.x) * 0.5, (target_a.y + target_b.y) * 0.5)
            snap_index = RoadSnapIndex(graph, cell_size_m=500.0)
            start_snap = snap_index.snap(*start_xy)
            target_snap = snap_index.snap(*target_xy)
            assert start_snap is not None and target_snap is not None
            router = GraphRouter(graph)

            for preference in RoutingPreference:
                with self.subTest(preference=preference.value):
                    python_result = router.route_snaps(start_snap, target_snap, EdgeCostPolicy(preference))
                    completed = subprocess.run(
                        [str(cli), str(start_xy[0]), str(start_xy[1]), str(target_xy[0]), str(target_xy[1]),
                         str(graph_path), str(snap_path), preference.value],
                        cwd=ROOT, check=False, capture_output=True, text=True,
                    )
                    native = json.loads(completed.stdout)
                    self.assertEqual(native["success"], python_result.success)
                    self.assertTrue(python_result.success)
                    self.assertEqual(native["edge_indices"], [step.edge_index for step in python_result.steps])
                    self.assertAlmostEqual(native["distance_m"], python_result.distance_m, delta=1e-3)
                    self.assertAlmostEqual(native["travel_time_s"], python_result.travel_time_s, delta=1e-4)

            oneway_graph, _ = build_graph([
                way(99, [10, 11], [(14.0, 56.0), (14.002, 56.0)], highway="primary", oneway="yes", maxspeed="60"),
            ])
            oneway_graph_path = temp / "oneway.brg"
            oneway_snap_path = temp / "oneway.brs"
            write_brg1(oneway_graph, oneway_graph_path)
            oneway_graph = load_brg1(oneway_graph_path)
            build_snap_index(oneway_graph, oneway_snap_path, cell_size_m=500.0)
            n10 = oneway_graph.nodes[node_index(oneway_graph, 10)]
            n11 = oneway_graph.nodes[node_index(oneway_graph, 11)]
            index = RoadSnapIndex(oneway_graph, cell_size_m=500.0)
            reverse_start = index.snap(n11.x, n11.y, 5.0)
            reverse_target = index.snap(n10.x, n10.y, 5.0)
            assert reverse_start is not None and reverse_target is not None
            python_reverse = GraphRouter(oneway_graph).route_snaps(
                reverse_start, reverse_target, EdgeCostPolicy(RoutingPreference.FASTEST)
            )
            completed = subprocess.run(
                [str(cli), str(n11.x), str(n11.y), str(n10.x), str(n10.y),
                 str(oneway_graph_path), str(oneway_snap_path), "fastest"],
                cwd=ROOT, check=False, capture_output=True, text=True,
            )
            native_reverse = json.loads(completed.stdout)
            self.assertFalse(python_reverse.success)
            self.assertFalse(native_reverse["success"])
            self.assertEqual(native_reverse.get("failure_reason"), "unreachable")


if __name__ == "__main__":
    unittest.main()
