"""Guard BMC2 production output, normalized cache composition and coastline truth."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

from shapely.geometry import LineString, Point, Polygon

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from benchmark_issue_220 import (
    BASELINE_FINALIZE_SECONDS,
    EXPECTED_HIGHWAY_NODES,
    EXPECTED_HIGHWAY_WAYS,
    EXPECTED_SOURCE_SHA256,
    EXPECTED_SOURCE_SIZE,
    MAX_COLD_SECONDS,
    MAX_WARM_SECONDS,
)
from build_background import WATER, background_class, solve_coastline_land
from world_build_plan import parse_targets, required_source_routes


class Tests(unittest.TestCase):
    def test_buildings_use_shared_assembled_area_cache_then_bmc2(self):
        text = (TOOLS / "build_sweden.py").read_text(encoding="utf-8")
        run = text[text.index("def _run_target") : text.index("def main()")]
        buildings = run.index('build_buildings(sources["areas"], output)')
        mesh = run.index("build_building_mesh_pyramid(output)")
        self.assertLess(buildings, mesh)
        self.assertNotIn("build_building_tiles", text)

    def test_pois_and_background_share_finished_area_facts_without_reassembly(self):
        text = (TOOLS / "build_sweden.py").read_text(encoding="utf-8")
        self.assertIn('build_pois(sources["pois"], output, sources["areas"])', text)
        self.assertIn('build_background_sources(sources["areas"], output)', text)
        self.assertIn('build_buildings(sources["areas"], output)', text)
        self.assertNotIn('sources["background_areas"]', text)
        self.assertNotIn('sources["buildings"]', text)

    def test_target_dependency_closure_is_minimal(self):
        self.assertEqual(required_source_routes(parse_targets("routing")), ("highways",))
        self.assertEqual(required_source_routes(parse_targets("buildings")), ("areas",))
        self.assertEqual(required_source_routes(parse_targets("pois")), ("pois", "areas"))
        self.assertEqual(required_source_routes(parse_targets("traffic")), ("traffic_signals", "highways"))
        self.assertEqual(required_source_routes(parse_targets("background")), ("areas",))

    def test_admin_boundary_is_not_land_truth(self):
        self.assertIsNone(background_class({"boundary": "administrative", "admin_level": "2"}))

    def test_directed_coastline_selects_land_side_not_whole_admin_domain(self):
        domain = Polygon([(-100, -100), (100, -100), (100, 100), (-100, 100), (-100, -100)])
        coastline = LineString([(0, -100), (0, 100)])
        land = solve_coastline_land([domain], [coastline])
        self.assertTrue(land.covers(Point(-50, 0)))
        self.assertFalse(land.covers(Point(50, 0)))

    def test_inland_natural_water_remains_water(self):
        self.assertEqual(background_class({"natural": "water"}), WATER)

    def test_real_sweden_benchmark_contract_matches_issue_baseline(self):
        self.assertEqual(EXPECTED_SOURCE_SHA256, "5c9682d34aeac727487c06f1bbe22b5976de5c3ada5723c0e446bda3bb316cd2")
        self.assertEqual(EXPECTED_SOURCE_SIZE, 814_508_417)
        self.assertEqual(EXPECTED_HIGHWAY_NODES, 25_418_811)
        self.assertEqual(EXPECTED_HIGHWAY_WAYS, 2_290_999)
        self.assertEqual(BASELINE_FINALIZE_SECONDS, 5329.7)
        self.assertEqual(MAX_COLD_SECONDS, 2664.85)
        self.assertEqual(MAX_WARM_SECONDS, 30.0)


if __name__ == "__main__":
    unittest.main()
