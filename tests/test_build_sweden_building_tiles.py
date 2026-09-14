"""Guard the full Sweden build's canonical production building representation."""

from __future__ import annotations

import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

class Tests(unittest.TestCase):
    def test_buildings_produce_bmc2_without_legacy_building_tiles(self):
        text=(ROOT/"tools"/"build_sweden.py").read_text(encoding="utf-8")
        run=text[text.index("def _run_target") : text.index("def main()")]
        buildings=run.index('build_buildings(sources["areas"], output)')
        mesh=run.index("build_building_mesh_pyramid(output)")
        lights=run.index("build_city_light_density(output)")
        self.assertLess(buildings,mesh); self.assertLess(mesh,lights)
        self.assertNotIn("build_building_tiles",text)
        self.assertIn("BMC2 is the canonical production building representation",text)

if __name__=="__main__": unittest.main()
