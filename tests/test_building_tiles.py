"""Tests the derived production building-tile cache and its cheap reuse contract.

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

from build_building_tiles import (  # noqa: E402
    BUILDING_TILE_FORMAT_VERSION,
    build_building_tiles,
    building_tiles_cache_valid,
)


class BuildingTileTests(unittest.TestCase):
    def _make_world(self, directory: str) -> Path:
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
        return world

    def test_building_tiles_are_derived_manifested_and_reusable(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            world = self._make_world(directory)

            report = build_building_tiles(world, tile_size=2000.0)

            self.assertIs(report["source_rebuilt"], False)
            self.assertEqual(report["source"], "buildings.jsonl")
            self.assertEqual(report["records"], 3)
            self.assertEqual(report["tile_count"], 3)
            self.assertEqual(report["format_version"], BUILDING_TILE_FORMAT_VERSION)
            self.assertTrue((world / "building_tiles" / "0_0.jsonl").is_file())
            self.assertTrue((world / "building_tiles" / "1_0.jsonl").is_file())
            self.assertTrue((world / "building_tiles" / "-1_-1.jsonl").is_file())

            manifest = json.loads((world / "manifest.json").read_text(encoding="utf-8"))
            features = manifest["features"]
            self.assertEqual(features["building_tiles_dir"], "building_tiles")
            self.assertEqual(features["building_tile_size"], 2000.0)
            self.assertEqual(features["building_tile_format_version"], BUILDING_TILE_FORMAT_VERSION)
            self.assertEqual(features["runtime_buildings_total"], 3)
            self.assertEqual(features["buildings"], 3)
            self.assertTrue(building_tiles_cache_valid(world, 2000.0))

    def test_cache_becomes_stale_when_authoritative_source_changes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            world = self._make_world(directory)
            build_building_tiles(world)
            buildings = world / "buildings.jsonl"
            buildings.write_text(
                buildings.read_text(encoding="utf-8")
                + json.dumps({"id": "d", "x": 500.0, "y": 500.0, "geometry": [], "tags": {"building": "yes"}})
                + "\n",
                encoding="utf-8",
            )
            self.assertFalse(building_tiles_cache_valid(world))

    def test_cache_becomes_stale_when_builder_contract_metadata_changes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            world = self._make_world(directory)
            build_building_tiles(world)
            manifest_path = world / "manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["features"]["building_tiles_builder_sha256"] = "stale"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            self.assertFalse(building_tiles_cache_valid(world))

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
            self.assertTrue(building_tiles_cache_valid(world, 2000.0))


if __name__ == "__main__":
    unittest.main()
