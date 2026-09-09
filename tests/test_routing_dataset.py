"""Correctness tests for publishing BRG1/BRS2/BRH1 as one routing dataset.

Dependencies:
- Uses build_routing_dataset.py with the production tiny OSM fixture pipeline.
- Verifies publication metadata and failure preservation without Godot or Sweden data.
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from build_routing_dataset import DATASET_FORMAT, build_routing_dataset
from route_geometry import RouteGeometryView
from routing_graph_view import RoutingGraphView


class RoutingDatasetTests(unittest.TestCase):
    def test_build_publishes_graph_snap_and_geometry_from_one_fixture(self) -> None:
        fixture = ROOT / "tests" / "fixtures" / "routing_minimal.osm"
        with tempfile.TemporaryDirectory(prefix="brur-routing-dataset-") as temp_dir:
            output = Path(temp_dir)
            report = build_routing_dataset(fixture, output)

            for name in ("routing.brg", "routing_snap.brs", "routing_geometry.brh", "routing_stats.json"):
                self.assertTrue((output / name).is_file(), name)
            self.assertEqual(report["routing_dataset_format"], DATASET_FORMAT)
            disk_report = json.loads((output / "routing_stats.json").read_text(encoding="utf-8"))
            self.assertEqual(disk_report["routing_dataset_format"], DATASET_FORMAT)

            geometry = RouteGeometryView.load(output / "routing_geometry.brh")
            with RoutingGraphView(output / "routing.brg") as graph:
                self.assertEqual(geometry.edge_count, len(graph.edges))

    def test_failed_snap_build_preserves_existing_published_dataset(self) -> None:
        fixture = ROOT / "tests" / "fixtures" / "routing_minimal.osm"
        with tempfile.TemporaryDirectory(prefix="brur-routing-dataset-failure-") as temp_dir:
            output = Path(temp_dir)
            sentinels = {
                "routing.brg": b"old-graph",
                "routing_snap.brs": b"old-snap",
                "routing_geometry.brh": b"old-geometry",
                "routing_stats.json": b"old-stats",
            }
            for name, content in sentinels.items():
                (output / name).write_bytes(content)

            with patch("build_routing_dataset.build_snap_index", side_effect=RuntimeError("snap failed")):
                with self.assertRaisesRegex(RuntimeError, "snap failed"):
                    build_routing_dataset(fixture, output)

            for name, content in sentinels.items():
                self.assertEqual((output / name).read_bytes(), content)
            self.assertFalse((output / ".routing_dataset.tmp").exists())


if __name__ == "__main__":
    unittest.main()
