"""Guard canonical BMC2 output, directed planning and coastline background truth."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

from shapely.geometry import LineString, Point, Polygon

ROOT=Path(__file__).resolve().parents[1]
TOOLS=ROOT/"tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0,str(TOOLS))

from build_background import WATER, background_class, solve_coastline_land  # noqa: E402
from world_build_plan import make_plan, parse_targets, record_target, required_source_routes  # noqa: E402


class Tests(unittest.TestCase):
    def _manifest(self):
        return {"source":{"algorithm":"sha256","digest":"abc","size_bytes":10},"routes":{
            "highways":{"complete":True,"version":2,"file":"highways.osm","size_bytes":1},
            "traffic_signals":{"complete":True,"version":2,"file":"traffic_signals.osm","size_bytes":1},
            "pois":{"complete":True,"version":2,"file":"pois.osm","size_bytes":1},
            "addresses":{"complete":True,"version":2,"file":"addresses.osm","size_bytes":1},
            "areas":{"complete":True,"version":2,"file":"areas.baf","size_bytes":1},
        }}

    def test_buildings_produce_bmc2_without_legacy_building_tiles(self):
        text=(ROOT/"tools"/"build_sweden.py").read_text(encoding="utf-8")
        run=text[text.index("def _run_target") : text.index("def main()")]
        buildings=run.index('build_buildings(sources["areas"], output)')
        mesh=run.index("build_building_mesh_pyramid(output)")
        self.assertLess(buildings,mesh)
        self.assertNotIn("build_building_tiles",text)
        self.assertIn("BMC2 is the canonical production building representation",text)

    def test_pois_own_relation_areas_and_city_light_density(self):
        text=(ROOT/"tools"/"build_sweden.py").read_text(encoding="utf-8")
        run=text[text.index("def _run_target") : text.index("def main()")]
        self.assertIn('build_pois(sources["pois"], output, sources["areas"])',run)
        self.assertIn("build_city_light_density(output)",run)
        buildings_block=run[run.index('elif target == "buildings"'):run.index('elif target == "search"')]
        self.assertNotIn("build_city_light_density",buildings_block)

    def test_target_dependency_closure_is_minimal(self):
        self.assertEqual(parse_targets("routing"),("routing",))
        self.assertEqual(required_source_routes(parse_targets("routing")),("highways",))
        self.assertEqual(parse_targets("buildings"),("buildings",))
        self.assertEqual(required_source_routes(parse_targets("buildings")),("areas",))
        self.assertEqual(parse_targets("pois"),("pois",))
        self.assertEqual(required_source_routes(parse_targets("pois")),("pois","areas"))

    def test_unrelated_dependency_change_does_not_invalidate_routing(self):
        with tempfile.TemporaryDirectory() as temp:
            world=Path(temp)
            for name in ("routing.brg","routing_geometry.brh","routing_snap.brs","routing_stats.json"):
                (world/name).write_bytes(b"x")
            first=next(p for p in make_plan(TOOLS,world,self._manifest(),("routing",)) if p.target=="routing")
            self.assertEqual(first.status,"REBUILD")
            record_target(world,"routing",first.fingerprint or "",1.0)
            manifest=self._manifest(); manifest["routes"]["addresses"]["version"]+=1
            unchanged=next(p for p in make_plan(TOOLS,world,manifest,("routing",)) if p.target=="routing")
            self.assertEqual(unchanged.status,"CACHE HIT")
            manifest["routes"]["highways"]["version"]+=1
            changed=next(p for p in make_plan(TOOLS,world,manifest,("routing",)) if p.target=="routing")
            self.assertEqual(changed.status,"REBUILD")

    def test_incomplete_dependency_is_blocked(self):
        manifest=self._manifest(); manifest["routes"]["areas"]["complete"]=False
        with tempfile.TemporaryDirectory() as temp:
            item=next(p for p in make_plan(TOOLS,Path(temp),manifest,("background",)) if p.target=="background")
            self.assertEqual(item.status,"BLOCKED")

    def test_plan_fails_closed_when_manifest_route_file_is_missing(self):
        with tempfile.TemporaryDirectory() as temp:
            world=Path(temp); cache=world/"osm_source_cache"; cache.mkdir()
            item=next(
                p for p in make_plan(TOOLS,world,self._manifest(),("routing",),cache)
                if p.target=="routing"
            )
            self.assertEqual(item.status,"BLOCKED")

    def test_admin_boundary_is_not_land_truth(self):
        self.assertIsNone(background_class({"boundary":"administrative","admin_level":"2"}))

    def test_directed_coastline_selects_land_side_not_whole_admin_domain(self):
        domain=Polygon([(-100,-100),(100,-100),(100,100),(-100,100),(-100,-100)])
        # Projected coordinates are meters. OSM coastline direction says land is
        # on the left; south->north therefore selects the west half only.
        coastline=LineString([(0,-100),(0,100)])
        land=solve_coastline_land([domain],[coastline])
        self.assertTrue(land.covers(Point(-50,0)))
        self.assertFalse(land.covers(Point(50,0)))

    def test_inland_natural_water_remains_water(self):
        self.assertEqual(background_class({"natural":"water"}),WATER)


if __name__=="__main__": unittest.main()
