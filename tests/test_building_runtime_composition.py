"""Guards the production building composition against runtime-data drift.

Dependencies:
- Reads the scene/composition source as stable production configuration.
- Does not require Godot or world data.
"""

from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class BuildingRuntimeCompositionTests(unittest.TestCase):
    def test_production_uses_prebuilt_building_mesh_lod_and_default_off(self) -> None:
        scene = (ROOT / "scenes" / "main.tscn").read_text(encoding="utf-8")
        composition = (ROOT / "scripts" / "building_runtime_composition.gd").read_text(encoding="utf-8")
        builder = (ROOT / "tools" / "build_building_mesh_pyramid.py").read_text(encoding="utf-8")

        self.assertIn('tile_data_dir: String = "res://world_data/building_mesh_lod"', composition)
        self.assertIn("building_tile_size_m: float = 2000.0", composition)
        self.assertIn("LodLevel(0, 16_000.0, 3_500.0, True)", builder)
        self.assertIn("LodLevel(3, 2_000.0, 0.0, False)", builder)
        self.assertIn("streaming_enabled = false", scene)
        self.assertIn("max_cache_chunks = 96", scene)
        self.assertIn('building_layer_path = NodePath("../BuildingLayer")', scene)


if __name__ == "__main__":
    unittest.main()
