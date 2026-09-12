"""Tests the derived production building-tile cache.

Dependencies:
- Uses tools/build_building_tiles.py with temporary authoritative buildings.jsonl input.
- Does not require Sweden PBF or Godot.
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from build_building_tiles import build_building_tiles  # noqa: E402


class BuildingTileTests(unittest.TestCase):
    def test_building_tiles_are_derived_and_manifested(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            world = Path(directory) / "world_data"
            world.mkdir()
            (world / "manifest.json").write_text(
                json.dumps({"origin_x": 0.0, "origin_y": 0.0, "features": {"buildings": 3}}),
                encoding="utf-8",
            )
            records = [
                {"id": "a", "x": 100.0, "y": 100.0, "geometry": [], "tags": {"building": "yes"}},
                {"id": "b", "x": 2100.0, "y": 100.0, "geometry": [], "tags": {"building": "yes"}},
                {"id": "c", "x": -10.0, "y": -10.0, "geometry": [], "tags": {"building": "yes"}},
            ]
            (world / "buildings.jsonl").write_text(
                "\n".join(json.dumps(record) for record in records) + "\n",
                encoding="utf-8",
            )

            report = build_building_tiles(world, tile_size=2000.0)

            self.assertIs(report["source_rebuilt"], False)
            self.assertEqual(report["source"], "buildings.jsonl")
            self.assertEqual(report["records"], 3)
            self.assertEqual(report["tile_count"], 3)
            self.assertTrue((world / "building_tiles" / "0_0.jsonl").is_file())
            self.assertTrue((world / "building_tiles" / "1_0.jsonl").is_file())
            self.assertTrue((world / "building_tiles" / "-1_-1.jsonl").is_file())

            manifest = json.loads((world / "manifest.json").read_text(encoding="utf-8"))
            features = manifest["features"]
            self.assertEqual(features["building_tiles_dir"], "building_tiles")
            self.assertEqual(features["building_tile_size"], 2000.0)
            self.assertEqual(features["runtime_buildings_total"], 3)
            self.assertEqual(features["buildings"], 3)

    def test_rebuild_replaces_stale_tiles(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            world = Path(directory) / "world_data"
            world.mkdir()
            (world / "manifest.json").write_text("{}", encoding="utf-8")
            (world / "buildings.jsonl").write_text(
                json.dumps({"id": "a", "x": 100.0, "y": 100.0, "geometry": [], "tags": {"building": "yes"}}) + "\n",
                encoding="utf-8",
            )
            stale = world / "building_tiles"
            stale.mkdir()
            (stale / "999_999.jsonl").write_text("stale\n", encoding="utf-8")

            build_building_tiles(world, tile_size=2000.0)

            self.assertFalse((world / "building_tiles" / "999_999.jsonl").exists())
            self.assertTrue((world / "building_tiles" / "0_0.jsonl").is_file())


if __name__ == "__main__":
    unittest.main()
