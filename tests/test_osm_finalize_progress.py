"""Verify BOSC2 native-prefilter progress and no obsolete finalize spool."""

from __future__ import annotations

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

import osmium

ROOT=Path(__file__).resolve().parents[1]
TOOLS=ROOT/"tools"
if str(TOOLS) not in sys.path: sys.path.insert(0,str(TOOLS))
from osm_source_cache import build_source_caches  # noqa: E402

FIXTURE='''<?xml version="1.0" encoding="UTF-8"?><osm version="0.6"><node id="1" lon="18" lat="59.3"/><node id="2" lon="18.001" lat="59.3"/><way id="10"><nd ref="1"/><nd ref="2"/><tag k="highway" v="residential"/></way></osm>'''
class Copy(osmium.SimpleHandler):
    def __init__(self,w): super().__init__(); self.w=w
    def node(self,v): self.w.add_node(v)
    def way(self,v): self.w.add_way(v)
    def relation(self,v): self.w.add_relation(v)

def write_pbf(xml,pbf):
    with osmium.SimpleWriter(str(pbf),overwrite=True) as writer: Copy(writer).apply_file(str(xml))

class Tests(unittest.TestCase):
    def test_direct_route_progress_has_start_scan_done_and_no_finalize_spool(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); xml=root/"f.osm"; xml.write_text(FIXTURE,encoding="utf-8"); pbf=root/"f.osm.pbf"; write_pbf(xml,pbf)
            output=io.StringIO()
            with contextlib.redirect_stdout(output): build_source_caches(pbf,root/"cache",("highways",))
            text=output.getvalue()
            self.assertIn("[plan] highways",text)
            self.assertIn("[osm-source] START native-prefiltered routes=highways",text)
            self.assertIn("[osm-source] python-visible:",text)
            self.assertIn("[osm-source] DONE route=highways",text)
            self.assertNotIn("finalizing: selecting spool records",text)
            self.assertFalse((root/"cache"/"resume-spool").exists())

    def test_warm_reuse_reports_cache_hit(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); xml=root/"f.osm"; xml.write_text(FIXTURE,encoding="utf-8"); pbf=root/"f.osm.pbf"; write_pbf(xml,pbf)
            cache=root/"cache"; build_source_caches(pbf,cache,("highways",))
            output=io.StringIO()
            with contextlib.redirect_stdout(output): build_source_caches(pbf,cache,("highways",))
            self.assertIn("CACHE HIT",output.getvalue())

if __name__=="__main__": unittest.main()
