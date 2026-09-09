"""Automatic tests for the cache-local fixed-point BCH2 sidecar.

Dependencies:
- Uses fixture-scale gps_ch construction and gps_bch2 serialization only.
- Does not require native code, Godot or Sweden data.
"""

from __future__ import annotations

import struct
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from gps_bch2 import HEADER, I32, MAGIC, U32, VERSION, quantize_cost, weight_scale, write_bch2
from gps_ch import build_ch
from gps_routing import EdgeCostPolicy, RoutingPreference
from routing_graph import RoutingProfile, WayInput, build_graph


def way(way_id: int, node_ids: list[int], coords: list[tuple[float, float]], **tags: str) -> WayInput:
    return WayInput(way_id, node_ids, coords, tags)


class Bch2Tests(unittest.TestCase):
    def test_layout_offsets_and_quantized_weights_are_explicit(self) -> None:
        graph, _ = build_graph(
            [
                way(1, [1, 2], [(13.0, 55.0), (13.001, 55.0)], highway="primary", maxspeed="80"),
                way(2, [2, 3], [(13.001, 55.0), (13.002, 55.0)], highway="secondary", maxspeed="60"),
            ]
        )
        policy = EdgeCostPolicy(RoutingPreference.FASTEST)
        index = build_ch(graph, RoutingProfile.NORMAL, policy)

        with tempfile.TemporaryDirectory(prefix="brur-bch2-") as temp_dir:
            path = Path(temp_dir) / "routing.bch2"
            stats = write_bch2(index, path)
            raw = path.read_bytes()

        values = HEADER.unpack_from(raw, 0)
        self.assertEqual(values[0], MAGIC)
        self.assertEqual(values[1], VERSION)
        self.assertEqual(values[2], len(graph.nodes))
        self.assertEqual(values[3], len(index.edges))
        self.assertEqual(values[7], weight_scale(RoutingPreference.FASTEST))
        self.assertAlmostEqual(values[8], policy.avoid_penalty)
        self.assertEqual(values[-1], len(raw))
        self.assertEqual(stats["output_bytes"], len(raw))

        source_offset, target_offset, weight_offset = values[10], values[11], values[12]
        original_offset, left_offset, right_offset = values[13], values[14], values[15]
        for edge_index, edge in enumerate(index.edges):
            self.assertEqual(U32.unpack_from(raw, source_offset + edge_index * 4)[0], edge.source_index)
            self.assertEqual(U32.unpack_from(raw, target_offset + edge_index * 4)[0], edge.target_index)
            self.assertEqual(
                U32.unpack_from(raw, weight_offset + edge_index * 4)[0],
                quantize_cost(edge.cost, values[7]),
            )
            self.assertEqual(I32.unpack_from(raw, original_offset + edge_index * 4)[0], edge.original_edge_index)
            self.assertEqual(I32.unpack_from(raw, left_offset + edge_index * 4)[0], edge.left_child)
            self.assertEqual(I32.unpack_from(raw, right_offset + edge_index * 4)[0], edge.right_child)

    def test_shortest_and_time_metrics_use_bounded_uint32_scales(self) -> None:
        self.assertEqual(weight_scale(RoutingPreference.SHORTEST), 1_000)
        self.assertEqual(weight_scale(RoutingPreference.FASTEST), 1_000_000)
        self.assertEqual(quantize_cost(12.345, 1_000), 12_345)
        with self.assertRaises(OverflowError):
            quantize_cost(float(1 << 32), 1_000_000)


if __name__ == "__main__":
    unittest.main()
