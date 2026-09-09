"""Compare the portable C++ BCH2 runtime against the exact Python CH reference.

Dependencies:
- Compiles native/gps_ch_runtime.cpp plus its file/CLI adapter.
- Uses fixture-scale gps_ch + gps_bch2 builders only; no Sweden data or Godot.
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

from gps_bch2 import weight_scale, write_bch2
from gps_ch import CHGraphRouter, build_ch
from gps_routing import EdgeCostPolicy, RoutingPreference
from routing_graph import RoutingProfile, WayInput, build_graph

SOURCE = ROOT / "native" / "gps_ch_runtime.cpp"
CLI = ROOT / "native" / "gps_ch_cli.cpp"

PREFERENCE_CODE = {
    RoutingPreference.FASTEST: 0,
    RoutingPreference.SHORTEST: 1,
    RoutingPreference.AVOID_SMALL_ROADS: 2,
    RoutingPreference.AVOID_MAJOR_ROADS: 3,
}


def way(way_id: int, node_ids: list[int], coords: list[tuple[float, float]], **tags: str) -> WayInput:
    return WayInput(way_id, node_ids, coords, tags)


class NativeGpsChParityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.compiler = os.environ.get("CXX") or shutil.which("clang++") or shutil.which("g++")

    def test_all_pairs_match_python_reference_for_all_preferences(self) -> None:
        if not self.compiler:
            self.skipTest("no C++20 compiler available")

        graph, _ = build_graph(
            [
                way(10, [1, 2], [(13.0, 55.0), (13.001, 55.0)], highway="primary", maxspeed="90"),
                way(20, [2, 3], [(13.001, 55.0), (13.002, 55.0)], highway="residential", maxspeed="30"),
                way(30, [1, 4, 3], [(13.0, 55.0), (13.001, 55.001), (13.002, 55.0)], highway="secondary", maxspeed="70"),
                way(40, [3, 5], [(13.002, 55.0), (13.003, 55.0)], highway="tertiary", maxspeed="50", oneway="yes"),
            ]
        )

        with tempfile.TemporaryDirectory(prefix="brur-native-ch-parity-") as temp_dir:
            temp = Path(temp_dir)
            cli = temp / "gps_ch_cli"
            subprocess.run(
                [
                    self.compiler,
                    "-std=c++20",
                    "-O2",
                    "-Wall",
                    "-Wextra",
                    "-pedantic",
                    str(SOURCE),
                    str(CLI),
                    "-o",
                    str(cli),
                ],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )

            for preference in RoutingPreference:
                policy = EdgeCostPolicy(preference)
                index = build_ch(graph, RoutingProfile.NORMAL, policy)
                bch_path = temp / f"{preference.value}.bch2"
                write_bch2(index, bch_path)
                reference = CHGraphRouter(graph, RoutingProfile.NORMAL, index)
                tolerance = 8.0 / weight_scale(preference)

                for start in range(len(graph.nodes)):
                    for target in range(len(graph.nodes)):
                        with self.subTest(preference=preference.value, start=start, target=target):
                            expected = reference.route_nodes(start, target, policy)
                            completed = subprocess.run(
                                [
                                    str(cli),
                                    str(bch_path),
                                    str(start),
                                    str(target),
                                    str(PREFERENCE_CODE[preference]),
                                    str(policy.avoid_penalty),
                                ],
                                cwd=ROOT,
                                check=True,
                                capture_output=True,
                                text=True,
                            )
                            actual = json.loads(completed.stdout)
                            self.assertEqual(actual["success"], expected.success)
                            if not expected.success:
                                self.assertEqual(actual["failure"], "unreachable")
                                continue
                            self.assertAlmostEqual(actual["cost"], expected.cost, delta=tolerance)
                            self.assertEqual(actual["edges"], [step.edge_index for step in expected.steps])
                            self.assertGreaterEqual(actual["settled"], 0)
                            self.assertGreaterEqual(actual["relaxed"], 0)
                            self.assertGreaterEqual(actual["queue_peak"], 0)
                            self.assertGreaterEqual(actual["state_peak"], 0)


if __name__ == "__main__":
    unittest.main()
