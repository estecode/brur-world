"""Verify BOSC4 invalidation and fail-closed normalized cache publication."""
from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import osmium

ROOT=Path(__file__).resolve().parents[1]; TOOLS=ROOT/"tools"
if str(TOOLS) not in sys.path: sys.path.insert(0,str(TOOLS))

import osm_source_cache
from osm_source_cache import ROUTE_VERSIONS, build_source_caches

FIXTURE='''<?xml version="1.0" encoding="UTF-8"?><osm version="0.6">
<node id="1" lon="18" lat="59.3"/><node id="2" lon="18.001" lat="59.3"/>
<way id="10"><nd ref="1"/><nd ref="2"/><tag k="highway" v="residential"/></way></osm>'''

class Copy(osmium.SimpleHandler):
    def __init__(self,writer): super().__init__(); self.writer=writer
    def node(self,value): self.writer.add_node(value)
    def way(self,value): self.writer.add_way(value)
    def relation(self,value): self.writer.add_relation(value)

def write_pbf(xml:Path,pbf:Path)->None:
    with osmium.SimpleWriter(str(pbf),overwrite=True) as writer: Copy(writer).apply_file(str(xml))

class Tests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.root=Path(self.temp.name)
        xml=self.root/"f.osm"; xml.write_text(FIXTURE,encoding="utf-8"); self.pbf=self.root/"f.osm.pbf"; write_pbf(xml,self.pbf); self.cache=self.root/"cache"
    def tearDown(self): self.temp.cleanup()

    def test_changed_block_version_invalidates_only_that_block(self):
        build_source_caches(self.pbf,self.cache,("highways","addresses"))
        original=ROUTE_VERSIONS["addresses"]
        real=osm_source_cache.build_fast_facts
        try:
            ROUTE_VERSIONS["addresses"]=original+1
            with mock.patch.object(osm_source_cache,"build_fast_facts",wraps=real) as build:
                build_source_caches(self.pbf,self.cache,("highways","addresses"))
            self.assertEqual(build.call_count,1); self.assertEqual(set(build.call_args.args[1]),{"addresses"})
        finally: ROUTE_VERSIONS["addresses"]=original

    def test_tampered_cache_forces_only_that_block_rebuild(self):
        build_source_caches(self.pbf,self.cache,("highways","addresses"))
        path=self.cache/"addresses.brfacts"
        data=bytearray(path.read_bytes()); data[12]=data[12]^1; path.write_bytes(data); os.utime(path,None)
        real=osm_source_cache.build_fast_facts
        with mock.patch.object(osm_source_cache,"build_fast_facts",wraps=real) as build:
            build_source_caches(self.pbf,self.cache,("highways","addresses"))
        self.assertEqual(build.call_count,1); self.assertEqual(set(build.call_args.args[1]),{"addresses"})

    def test_interrupted_fast_pass_never_marks_block_complete(self):
        def broken(source,outputs):
            destination=next(iter(outputs.values())); destination.write_bytes(b"partial"); raise RuntimeError("boom")
        with mock.patch.object(osm_source_cache,"build_fast_facts",side_effect=broken):
            with self.assertRaises(RuntimeError): build_source_caches(self.pbf,self.cache,("highways",))
        manifest=self.cache/"manifest.json"
        if manifest.is_file():
            entry=json.loads(manifest.read_text(encoding="utf-8")).get("routes",{}).get("highways",{})
            self.assertIsNot(entry.get("complete"),True)
        run=json.loads((self.cache/"last_run.json").read_text(encoding="utf-8")); self.assertEqual(run["status"],"ERROR")

    def test_changed_authoritative_source_invalidates_requested_blocks_in_one_pass(self):
        build_source_caches(self.pbf,self.cache,("highways","addresses"))
        changed=self.root/"changed.osm"; changed.write_text(FIXTURE.replace("residential","service"),encoding="utf-8")
        self.pbf.unlink(); write_pbf(changed,self.pbf)
        real=osm_source_cache.build_fast_facts
        with mock.patch.object(osm_source_cache,"build_fast_facts",wraps=real) as build:
            build_source_caches(self.pbf,self.cache,("highways","addresses"))
        self.assertEqual(build.call_count,1); self.assertEqual(set(build.call_args.args[1]),{"highways","addresses"})

if __name__=="__main__": unittest.main()
