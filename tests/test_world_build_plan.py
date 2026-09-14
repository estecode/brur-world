"""Deterministic tests for selective target planning and directed invalidation."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
TOOLS=ROOT/"tools"
if str(TOOLS) not in sys.path: sys.path.insert(0,str(TOOLS))
from world_build_plan import make_plan, parse_targets, record_target, required_source_routes  # noqa: E402

class Tests(unittest.TestCase):
    def manifest(self):
        return {"source":{"algorithm":"sha256","digest":"abc","size_bytes":10},"routes":{
            "highways":{"complete":True,"version":2,"file":"highways.osm","size_bytes":1},
            "traffic_signals":{"complete":True,"version":2,"file":"traffic_signals.osm","size_bytes":1},
            "pois":{"complete":True,"version":2,"file":"pois.osm","size_bytes":1},
            "addresses":{"complete":True,"version":2,"file":"addresses.osm","size_bytes":1},
            "areas":{"complete":True,"version":2,"file":"areas.baf","size_bytes":1},
        }}

    def test_target_closure_is_minimal(self):
        self.assertEqual(parse_targets("routing"),("routing",))
        self.assertEqual(required_source_routes(parse_targets("routing")),("highways",))
        self.assertEqual(parse_targets("buildings"),("buildings",))
        self.assertEqual(required_source_routes(parse_targets("buildings")),("areas",))
        self.assertEqual(parse_targets("pois"),("pois",))
        self.assertEqual(required_source_routes(parse_targets("pois")),("pois","areas"))

    def test_unrelated_targets_are_skip(self):
        with tempfile.TemporaryDirectory() as temp:
            plan=make_plan(TOOLS,Path(temp),self.manifest(),("routing",))
            status={p.target:p.status for p in plan}
            self.assertEqual(status["routing"],"REBUILD")
            self.assertEqual(status["search"],"SKIP")
            self.assertEqual(status["background"],"SKIP")

    def test_exact_fingerprint_becomes_hit_and_changed_dependency_rebuilds_only_owner(self):
        with tempfile.TemporaryDirectory() as temp:
            world=Path(temp)
            for name in ("routing.brg","routing_geometry.brh","routing_snap.brs","routing_stats.json"):
                (world/name).write_bytes(b"x")
            first=next(p for p in make_plan(TOOLS,world,self.manifest(),("routing",)) if p.target=="routing")
            self.assertEqual(first.status,"REBUILD")
            record_target(world,"routing",first.fingerprint or "",1.0)
            hit=next(p for p in make_plan(TOOLS,world,self.manifest(),("routing",)) if p.target=="routing")
            self.assertEqual(hit.status,"CACHE HIT")
            changed=self.manifest(); changed["routes"]["addresses"]["version"]+=1
            still_hit=next(p for p in make_plan(TOOLS,world,changed,("routing",)) if p.target=="routing")
            self.assertEqual(still_hit.status,"CACHE HIT")
            changed["routes"]["highways"]["version"]+=1
            rebuild=next(p for p in make_plan(TOOLS,world,changed,("routing",)) if p.target=="routing")
            self.assertEqual(rebuild.status,"REBUILD")

    def test_incomplete_source_dependency_blocks(self):
        manifest=self.manifest(); manifest["routes"]["areas"]["complete"]=False
        with tempfile.TemporaryDirectory() as temp:
            item=next(p for p in make_plan(TOOLS,Path(temp),manifest,("background",)) if p.target=="background")
            self.assertEqual(item.status,"BLOCKED")

if __name__=="__main__": unittest.main()
