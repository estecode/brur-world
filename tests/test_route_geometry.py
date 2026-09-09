"""Regression tests for detailed route geometry preserved by the routing pipeline.

Dependencies:
- Uses the production XML routing builder for a tiny deterministic curved-road fixture.
- Uses route_geometry.py and routing_graph_view.py to verify BRH1/BRG1 edge alignment.
- Compiles the portable geometry helper and native GPS server when a C++20 compiler is available.
"""

from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from build_routing import build_routing
from gps_snap_index import build_snap_index
from route_geometry import (
    EDGE_RECORD as GEOMETRY_EDGE_RECORD,
    HEADER as GEOMETRY_HEADER,
    POINT_RECORD as GEOMETRY_POINT_RECORD,
    RouteGeometryView,
    validate_route_geometry_alignment,
)
from routing_graph_view import RoutingGraphView
from world_common import project, unproject


FIXTURE_XML = """<?xml version="1.0" encoding="UTF-8"?>
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
"""


def build_curved_fixture(temp: Path) -> tuple[Path, Path, tuple[tuple[float, float], ...]]:
    fixture = temp / "curve.osm"
    fixture.write_text(FIXTURE_XML, encoding="utf-8")
    build_routing(fixture, temp)
    graph_path = temp / "routing.brg"
    snap_path = temp / "routing_snap.brs"
    with RoutingGraphView(graph_path) as graph:
        build_snap_index(graph, snap_path, cell_size_m=500.0)
    expected = tuple(project(lon, lat) for lon, lat in (
        (18.0000, 59.0000),
        (18.0010, 59.0010),
        (18.0020, 59.0000),
    ))
    return graph_path, snap_path, expected


def free_local_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


class RouteGeometryTests(unittest.TestCase):
    def test_web_mercator_round_trip_matches_source_coordinates(self) -> None:
        lon, lat = 18.123456, 67.234567
        x, y = project(lon, lat)
        actual_lon, actual_lat = unproject(x, y)
        self.assertAlmostEqual(actual_lon, lon, places=9)
        self.assertAlmostEqual(actual_lat, lat, places=9)

    def test_compressed_curved_edge_preserves_shape_in_both_directions(self) -> None:
        with tempfile.TemporaryDirectory(prefix="brur-route-geometry-") as temp_dir:
            temp = Path(temp_dir)
            graph_path, _snap_path, expected = build_curved_fixture(temp)
            geometry = RouteGeometryView.load(temp / "routing_geometry.brh")
            with RoutingGraphView(graph_path) as graph:
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

            forward = geometry.edge_points(forward_index)
            reverse = geometry.edge_points(reverse_index)

            self.assertEqual(len(forward), 3, "curved compressed edge must not collapse to A/B")
            self.assertEqual(len(reverse), 3)
            for actual, wanted in zip(forward, expected):
                self.assertAlmostEqual(actual[0], wanted[0], delta=0.75)
                self.assertAlmostEqual(actual[1], wanted[1], delta=0.75)
            for actual, wanted in zip(reverse, reversed(expected)):
                self.assertAlmostEqual(actual[0], wanted[0], delta=0.75)
                self.assertAlmostEqual(actual[1], wanted[1], delta=0.75)

    def test_dataset_alignment_validator_rejects_collapsed_curved_shape(self) -> None:
        with tempfile.TemporaryDirectory(prefix="brur-route-geometry-invariant-") as temp_dir:
            temp = Path(temp_dir)
            graph_path, _snap_path, expected = build_curved_fixture(temp)
            geometry_path = temp / "routing_geometry.brh"

            report = validate_route_geometry_alignment(graph_path, geometry_path)
            self.assertEqual(int(report["edge_count"]), 2)

            payload = bytearray(geometry_path.read_bytes())
            _magic, edge_count, _point_count = GEOMETRY_HEADER.unpack_from(payload, 0)
            point_table_offset = GEOMETRY_HEADER.size + edge_count * GEOMETRY_EDGE_RECORD.size
            midpoint = (
                (expected[0][0] + expected[-1][0]) * 0.5,
                (expected[0][1] + expected[-1][1]) * 0.5,
            )
            GEOMETRY_POINT_RECORD.pack_into(
                payload,
                point_table_offset + GEOMETRY_POINT_RECORD.size,
                midpoint[0],
                midpoint[1],
            )
            geometry_path.write_bytes(payload)

            with self.assertRaisesRegex(ValueError, "geometry length mismatch"):
                validate_route_geometry_alignment(graph_path, geometry_path)

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

    def test_native_server_response_contains_curved_shape_point(self) -> None:
        compiler = os.environ.get("CXX") or shutil.which("clang++") or shutil.which("g++")
        if not compiler:
            self.skipTest("no C++20 compiler available")
        with tempfile.TemporaryDirectory(prefix="brur-route-geometry-server-") as temp_dir:
            temp = Path(temp_dir)
            graph_path, snap_path, expected = build_curved_fixture(temp)
            server_binary = temp / "brur-gps-server"
            subprocess.run(
                [compiler, "-std=c++20", "-O2", "-Wall", "-Wextra", "-pedantic",
                 str(ROOT / "native" / "gps_core.cpp"), str(ROOT / "native" / "gps_route_server.cpp"),
                 "-o", str(server_binary)],
                cwd=ROOT, check=True, capture_output=True, text=True,
            )

            port = free_local_port()
            server = subprocess.Popen(
                [str(server_binary), str(graph_path), str(snap_path), str(port)],
                cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            )
            try:
                connection: socket.socket | None = None
                deadline = time.monotonic() + 5.0
                while time.monotonic() < deadline:
                    if server.poll() is not None:
                        stderr = server.stderr.read() if server.stderr else ""
                        self.fail(f"native GPS server exited before accepting connections: {stderr}")
                    try:
                        connection = socket.create_connection(("127.0.0.1", port), timeout=0.25)
                        break
                    except OSError:
                        time.sleep(0.05)
                self.assertIsNotNone(connection, "native GPS server did not become ready")
                assert connection is not None
                with connection:
                    start = expected[0]
                    target = expected[-1]
                    request = f"{start[0]} {start[1]} {target[0]} {target[1]} fastest\n"
                    connection.sendall(request.encode("utf-8"))
                    received = b""
                    while b"\n" not in received:
                        chunk = connection.recv(65536)
                        if not chunk:
                            break
                        received += chunk
                payload = json.loads(received.split(b"\n", 1)[0].decode("utf-8"))
                self.assertTrue(payload["success"])
                points = payload["points"]
                self.assertGreaterEqual(len(points), 3, "server must return detailed curved geometry")
                bend = expected[1]
                self.assertTrue(
                    any(abs(float(point[0]) - bend[0]) <= 0.75 and abs(float(point[1]) - bend[1]) <= 0.75 for point in points),
                    "server response must include the intermediate road-shape point",
                )
            finally:
                server.terminate()
                try:
                    server.wait(timeout=2.0)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait(timeout=2.0)


if __name__ == "__main__":
    unittest.main()
