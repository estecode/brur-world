"""Deterministic tests for selective target planning and checksum invalidation."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path: sys.path.insert(0, str(TOOLS))

from world_build_plan import make_plan, parse_targets, record_target, required_source_routes


class Tests(unittest.TestCase):
    def manifest(self):
        routes = {}
        for name in ("highways", "traffic_signals", "pois", "addresses", "areas"):
            suffix = ".baf" if name == "areas" else ".brfacts"
            routes[name] = {
                "complete": True,
                "version": 1,
                "extractor_version": 2,
                "file": f"{name}{suffix}",
                "size_bytes": 1,
                "sha256": (name[0] * 64),
            }
        return {"source": {"algorithm":"sha256","digest":"abc","size_bytes":10}, "routes": routes}

    def test_target_closure_is_minimal_and_explicit(self):
        self.assertEqual(required_source_routes(parse_targets("routing")), ("highways",))
        self.assertEqual(required_source_routes(parse_targets("buildings")), ("areas",))
        self.assertEqual(required_source_routes(parse_targets("pois")), ("pois", "areas"))
        self.assertEqual(required_source_routes(parse_targets("traffic")), ("traffic_signals", "highways"))
        self.assertEqual(required_source_routes(parse_targets("background")), ("areas",))

    def test_unrelated_targets_are_skip(self):
        with tempfile.TemporaryDirectory() as temp:
            plan=make_plan(TOOLS,Path(temp),self.manifest(),("routing",)); status={i.target:i.status for i in plan}
            self.assertEqual(status["routing"],"REBUILD"); self.assertEqual(status["search"],"SKIP"); self.assertEqual(status["background"],"SKIP")

    def test_dependency_checksum_changes_only_downstream_owner(self):
        with tempfile.TemporaryDirectory() as temp:
            world=Path(temp)
            for name in ("routing.brg","routing_geometry.brh","routing_snap.brs","routing_stats.json"):(world/name).write_bytes(b"x")
            first=next(i for i in make_plan(TOOLS,world,self.manifest(),("routing",)) if i.target=="routing")
            record_target(world,"routing",first.fingerprint or "",1.0)
            manifest=self.manifest(); manifest["routes"]["addresses"]["sha256"]="f"*64
            still_hit=next(i for i in make_plan(TOOLS,world,manifest,("routing",)) if i.target=="routing")
            self.assertEqual(still_hit.status,"CACHE HIT")
            manifest["routes"]["highways"]["sha256"]="e"*64
            rebuild=next(i for i in make_plan(TOOLS,world,manifest,("routing",)) if i.target=="routing")
            self.assertEqual(rebuild.status,"REBUILD")

    def test_incomplete_source_dependency_blocks(self):
        manifest=self.manifest(); manifest["routes"]["areas"]["complete"]=False
        with tempfile.TemporaryDirectory() as temp:
            item=next(i for i in make_plan(TOOLS,Path(temp),manifest,("background",)) if i.target=="background")
            self.assertEqual(item.status,"BLOCKED")


if __name__=="__main__": unittest.main()
