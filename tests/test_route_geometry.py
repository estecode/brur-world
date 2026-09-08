"""Regression tests for detailed route geometry preserved by the routing pipeline.

Dependencies:
- Uses the production XML routing builder for a tiny deterministic curved-road fixture.
- Uses route_geometry.py and routing_graph_view.py to verify BRH1/BRG1 edge alignment.
- Compiles the portable native geometry densifier when a C++20 compiler is available.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from build_routing import build_routing
from route_geometry import RouteGeometryView
from routing_graph_view import RoutingGraphView
from world_common import project


class RouteGeometryTests(unittest.TestCase):
    def test_compressed_curved_edge_preserves_shape_in_both_directions(self) -> None:
        with tempfile.TemporaryDirectory(prefix="brur-route-geometry-") as temp_dir:
            temp = Path(temp_dir)
            fixture = temp / "curve.osm"
            fixture.write_text(
                """<?xml version="1.0" encoding="UTF-8"?>
<osm version="0.6">
  <node id="1" lat="59.0000" lon="18.0000" />
  <node id="2" lat="59.0010" lon="18.0010" />
  <node id="3" lat="59.0000" lon="18.0020" />
  <way id="10">
    <nd ref="1"/><nd ref="2"/><nd ref="3"/>
    <tag k="highway" v="residential"/>
    <tag k="maxspeed" v="40"/>
  </way>
</osm>
""",
                encoding="utf-8",
            )

            build_routing(fixture, temp)
            geometry = RouteGeometryView.load(temp / "routing_geometry.brh")
            with RoutingGraphView(temp / "routing.brg") as graph:
                self.assertEqual(len(graph.nodes), 2, "shape-only bend must remain compressed out of topology")
                self.assertEqual(len(graph.edges), 2)
                self.assertEqual(geometry.edge_count, len(graph.edges))

                forward_index = next(
                    index for index, edge in enumerate(graph.edges)
                    if graph.nodes[edge.source_index].osm_id == 1 and graph.nodes[edge.target_index].osm_id == 3
                )
                reverse_index = next(
                    index for index, edge in enumerate(graph.edges)
                    if graph.nodes[edge.source_index].osm_id == 3 and graph.nodes[edge.target_index].osm_id == 1
                )

            expected = tuple(project(lon, lat) for lon, lat in (
                (18.0000, 59.0000),
                (18.0010, 59.0010),
                (18.0020, 59.0000),
            ))
            forward = geometry.edge_points(forward_index)
            reverse = geometry.edge_points(reverse_index)

            self.assertEqual(len(forward), 3, "curved compressed edge must not collapse to A/B")
            self.assertEqual(len(reverse), 3)
            for actual, wanted in zip(forward, expected):
                self.assertAlmostEqual(actual[0], wanted[0], delta=0.25)
                self.assertAlmostEqual(actual[1], wanted[1], delta=0.25)
            for actual, wanted in zip(reverse, reversed(expected)):
                self.assertAlmostEqual(actual[0], wanted[0], delta=0.25)
                self.assertAlmostEqual(actual[1], wanted[1], delta=0.25)

    def test_portable_native_densifier(self) -> None:
        compiler = os.environ.get("CXX") or shutil.which("clang++") or shutil.which("g++")
        if not compiler:
            self.skipTest("no C++20 compiler available")
        with tempfile.TemporaryDirectory(prefix="brur-route-geometry-native-") as temp_dir:
            binary = Path(temp_dir) / "test_route_geometry"
            subprocess.run(
                [compiler, "-std=c++20", "-O2", "-Wall", "-Wextra", "-pedantic",
                 str(ROOT / "tests" / "native" / "test_route_geometry.cpp"), "-o", str(binary)],
                cwd=ROOT, check=True, capture_output=True, text=True,
            )
            completed = subprocess.run(
                [str(binary)], cwd=ROOT, check=True, capture_output=True, text=True,
            )
            self.assertEqual(completed.stdout.strip(), "native route geometry tests: OK")


if __name__ == "__main__":
    unittest.main()
