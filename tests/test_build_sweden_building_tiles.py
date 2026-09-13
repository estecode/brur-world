"""Guards the full Sweden build pipeline's production building derived-data stages."""

from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class BuildSwedenBuildingTileStageTests(unittest.TestCase):
    def test_full_build_derives_runtime_building_data_after_authoritative_buildings(self) -> None:
        text = (ROOT / "tools" / "build_sweden.py").read_text(encoding="utf-8")
        main = text[text.index("def main()") :]
        buildings = main.index('build_buildings(sources["areas"], args.output)')
        tiles = main.index("build_building_tiles(args.output)")
        mesh_lod = main.index("build_building_mesh_pyramid(args.output)")
        lights = main.index("build_city_light_density(args.output)")
        self.assertLess(buildings, tiles)
        self.assertLess(tiles, mesh_lod)
        self.assertLess(mesh_lod, lights)


if __name__ == "__main__":
    unittest.main()
