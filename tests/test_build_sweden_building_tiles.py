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

from benchmark_issue_220 import MAX_WARM_SECONDS, MIN_BUILDINGS, MINIMUM_COLD_BASELINE_SECONDS
from build_background import WATER, background_class, solve_coastline_land
from world_build_plan import parse_targets, required_source_routes


class Tests(unittest.TestCase):
    def test_buildings_use_shared_assembled_area_cache_then_bmc2(self):
        text = (TOOLS / "build_sweden.py").read_text(encoding="utf-8")
        run = text[text.index("def _run_target") : text.index("def _is_geopackage")]
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

    def test_real_sweden_benchmark_contract_uses_issue_gates_and_production_selection(self):
        self.assertEqual(MIN_BUILDINGS, 3_800_000)
        self.assertEqual(MINIMUM_COLD_BASELINE_SECONDS, 5329.7)
        self.assertEqual(MAX_WARM_SECONDS, 30.0)
        benchmark = (TOOLS / "benchmark_issue_220.py").read_text(encoding="utf-8")
        self.assertIn('parser.add_argument("gpkg"', benchmark)
        self.assertIn('parser.add_argument("--source-pbf"', benchmark)
        self.assertIn('"gpkg_and_pbf_hashes_recorded"', benchmark)
        self.assertIn('"no_provider_stage_cache"', benchmark)
        self.assertIn('"building_records_match_source"', benchmark)
        self.assertIn('"traffic_signals_match_source"', benchmark)
        self.assertIn('"cold_source_cache_at_least_2x_faster_than_minimum_baseline"', benchmark)
        self.assertIn('selected_runtime_files(world_dir)', benchmark)
        self.assertNotIn("full_world_build_under_15_minutes", benchmark)
        self.assertNotIn('"buildings.jsonl"', benchmark)


if __name__ == "__main__":
    unittest.main()
