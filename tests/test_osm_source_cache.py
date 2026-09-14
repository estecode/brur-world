"""Verify BOSC4 normalized source facts, one-pass fanout and warm reuse."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import osmium

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path: sys.path.insert(0, str(TOOLS))

import osm_source_cache
from normalized_source_facts import iter_facts
from osm_source_cache import ALL_ROUTES, CACHE_FORMAT, ROUTE_VERSIONS, build_source_caches

FIXTURE = """<?xml version="1.0" encoding="UTF-8"?>
<osm version="0.6">
  <node id="1" lon="18.0000" lat="59.3000"><tag k="highway" v="traffic_signals"/></node>
  <node id="2" lon="18.0010" lat="59.3000"/>
  <node id="3" lon="18.0020" lat="59.3000"><tag k="amenity" v="school"/><tag k="name" v="Fixture School"/></node>
  <node id="4" lon="18.0030" lat="59.3000"><tag k="addr:housenumber" v="12"/><tag k="addr:street" v="Testvägen"/></node>
  <node id="5" lon="18.0000" lat="59.3010"/>
  <way id="10"><nd ref="1"/><nd ref="2"/><tag k="highway" v="residential"/><tag k="maxspeed" v="50"/></way>
  <way id="20"><nd ref="1"/><nd ref="2"/><nd ref="5"/><nd ref="1"/><tag k="building" v="yes"/></way>
</osm>
"""

class Copy(osmium.SimpleHandler):
    def __init__(self, writer): super().__init__(); self.writer=writer
    def node(self, value): self.writer.add_node(value)
    def way(self, value): self.writer.add_way(value)
    def relation(self, value): self.writer.add_relation(value)

def write_pbf(xml:Path,pbf:Path)->None:
    with osmium.SimpleWriter(str(pbf),overwrite=True) as writer: Copy(writer).apply_file(str(xml))

class Tests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.root=Path(self.temp.name)
        xml=self.root/"fixture.osm"; xml.write_text(FIXTURE,encoding="utf-8")
        self.pbf=self.root/"fixture.osm.pbf"; write_pbf(xml,self.pbf); self.cache=self.root/"cache"
    def tearDown(self): self.temp.cleanup()

    def test_all_blocks_publish_normalized_versioned_manifest(self):
        outputs=build_source_caches(self.pbf,self.cache,ALL_ROUTES)
        self.assertEqual(set(outputs),set(ALL_ROUTES))
        manifest=json.loads((self.cache/"manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["format"],CACHE_FORMAT)
        for route in ALL_ROUTES:
            entry=manifest["routes"][route]
            self.assertTrue(entry["complete"]); self.assertEqual(entry["version"],ROUTE_VERSIONS[route])
            self.assertEqual(entry["extractor"],"pyosmium/libosmium"); self.assertEqual(len(entry["sha256"]),64)
            self.assertNotIn(".osm.pbf",entry["file"]); self.assertTrue(outputs[route].is_file())
        highway=list(iter_facts(outputs["highways"],1))
        self.assertEqual(len(highway),1); self.assertEqual(highway[0]["osm_id"],10); self.assertEqual(highway[0]["tags"]["maxspeed"],"50")

    def test_multiple_stale_simple_blocks_share_one_fast_pass(self):
        real=osm_source_cache.build_fast_facts
        with mock.patch.object(osm_source_cache,"build_fast_facts",wraps=real) as build:
            build_source_caches(self.pbf,self.cache,("highways","addresses","pois","traffic_signals"))
        self.assertEqual(build.call_count,1)
        self.assertEqual(set(build.call_args.args[1]),{"highways","addresses","pois","traffic_signals"})

    def test_selective_request_builds_only_requested_block(self):
        outputs=build_source_caches(self.pbf,self.cache,("traffic_signals",))
        self.assertEqual(set(outputs),{"traffic_signals"}); self.assertTrue((self.cache/"traffic_signals.brfacts").is_file()); self.assertFalse((self.cache/"areas.baf").exists())

    def test_valid_cache_never_traverses_source_again(self):
        build_source_caches(self.pbf,self.cache,("highways",))
        with mock.patch.object(osm_source_cache,"build_fast_facts",side_effect=AssertionError("unexpected PBF traversal")):
            reused=build_source_caches(self.pbf,self.cache,("highways",))
        self.assertTrue(reused["highways"].is_file())
        run=json.loads((self.cache/"last_run.json").read_text(encoding="utf-8"))
        self.assertEqual(run["blocks"]["highways"]["status"],"CACHE HIT")

    def test_unknown_route_fails_closed(self):
        with self.assertRaises(ValueError): build_source_caches(self.pbf,self.cache,("not-a-domain",))

if __name__=="__main__": unittest.main()
