"""Automatic tests for the BRS3 fixed-point road-segment snap sidecar.

Dependencies:
- Uses routing_graph fixtures and gps_snap_index_v3 offline writer only.
- Does not require Sweden data, Godot or native code.
"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from gps_snap_index_v3 import CELL, HEADER, MAGIC, NO_EDGE, SEGMENT, VERSION, build_snap_index_v3
from routing_graph import WayInput, build_graph


def way(way_id: int, node_ids: list[int], coords: list[tuple[float, float]], **tags: str) -> WayInput:
    return WayInput(way_id, node_ids, coords, tags)


class SnapIndexV3Tests(unittest.TestCase):
    def test_serializes_local_centimetres_and_legal_directions(self) -> None:
        graph, _ = build_graph(
            [
                way(10, [1, 2], [(13.0, 55.0), (13.001, 55.0)], highway="primary", maxspeed="90"),
                way(20, [2, 3], [(13.001, 55.0), (13.002, 55.0)], highway="secondary", maxspeed="70", oneway="yes"),
            ]
        )
        with tempfile.TemporaryDirectory(prefix="brur-brs3-") as temp_dir:
            path = Path(temp_dir) / "routing_snap_v3.brs"
            stats = build_snap_index_v3(graph, path, cell_size_m=100.0)
            raw = path.read_bytes()

        (
            magic,
            version,
            cell_size_cm,
            cell_count,
            segment_count,
            ref_count,
            origin_x,
            origin_y,
            max_speed,
            reserved,
        ) = HEADER.unpack_from(raw, 0)
        self.assertEqual(magic, MAGIC)
        self.assertEqual(version, VERSION)
        self.assertEqual(cell_size_cm, 10_000)
        self.assertEqual(segment_count, stats["segment_count"])
        self.assertEqual(cell_count, stats["cell_count"])
        self.assertEqual(ref_count, stats["reference_count"])
        self.assertEqual(reserved, 0)
        self.assertGreater(max_speed, 0.0)
        self.assertLessEqual(origin_x, min(node.x for node in graph.nodes))
        self.assertLessEqual(origin_y, min(node.y for node in graph.nodes))

        segment_offset = HEADER.size + cell_count * CELL.size
        segments = [SEGMENT.unpack_from(raw, segment_offset + index * SEGMENT.size) for index in range(segment_count)]
        self.assertTrue(any(forward != NO_EDGE and reverse != NO_EDGE for forward, reverse, *_ in segments))
        self.assertTrue(any((forward == NO_EDGE) != (reverse == NO_EDGE) for forward, reverse, *_ in segments))
        for _forward, _reverse, ax, ay, bx, by in segments:
            for value in (ax, ay, bx, by):
                self.assertIsInstance(value, int)
                self.assertGreaterEqual(value, -(1 << 31))
                self.assertLess(value, 1 << 31)


if __name__ == "__main__":
    unittest.main()
