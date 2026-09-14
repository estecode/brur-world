"""Guard canonical BMC2 output and selective Sweden build planning."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
TOOLS=ROOT/"tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0,str(TOOLS))

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
        lights=run.index("build_city_light_density(output)")
        self.assertLess(buildings,mesh); self.assertLess(mesh,lights)
        self.assertNotIn("build_building_tiles",text)
        self.assertIn("BMC2 is the canonical production building representation",text)

    def test_target_dependency_closure_is_minimal(self):
        self.assertEqual(parse_targets("routing"),("routing",))
        self.assertEqual(required_source_routes(parse_targets("routing")),("highways",))
        self.assertEqual(parse_targets("buildings"),("pois","buildings"))
        self.assertEqual(required_source_routes(parse_targets("buildings")),("pois","areas"))

    def test_unrelated_dependency_change_does_not_invalidate_routing(self):
        with tempfile.TemporaryDirectory() as temp:
            world=Path(temp)
            for name in ("routing.brg","routing_geometry.brh","routing_snap.brs"):
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


if __name__=="__main__": unittest.main()
