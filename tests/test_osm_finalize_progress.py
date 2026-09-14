"""Verify timestamped source-cache status reporting and persistent diagnostics."""
from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

import osmium

ROOT=Path(__file__).resolve().parents[1]; TOOLS=ROOT/"tools"
if str(TOOLS) not in sys.path: sys.path.insert(0,str(TOOLS))

from osm_source_cache import build_source_caches

FIXTURE='''<?xml version="1.0" encoding="UTF-8"?><osm version="0.6"><node id="1" lon="18" lat="59.3"/><node id="2" lon="18.001" lat="59.3"/><way id="10"><nd ref="1"/><nd ref="2"/><tag k="highway" v="residential"/></way></osm>'''

class Copy(osmium.SimpleHandler):
    def __init__(self,writer): super().__init__(); self.writer=writer
    def node(self,value): self.writer.add_node(value)
    def way(self,value): self.writer.add_way(value)
    def relation(self,value): self.writer.add_relation(value)

def write_pbf(xml,pbf):
    with osmium.SimpleWriter(str(pbf),overwrite=True) as writer: Copy(writer).apply_file(str(xml))

class Tests(unittest.TestCase):
    def test_status_has_timestamp_plan_cache_hit_and_persistent_report(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp); xml=root/"f.osm"; xml.write_text(FIXTURE,encoding="utf-8"); pbf=root/"f.osm.pbf"; write_pbf(xml,pbf); cache=root/"cache"; output=io.StringIO()
            with contextlib.redirect_stdout(output):
                build_source_caches(pbf,cache,("highways",)); build_source_caches(pbf,cache,("highways",))
            text=output.getvalue()
            self.assertRegex(text,r"\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}\] \[osm-source\]")
            self.assertIn("PLAN route=highways status=REBUILD",text); self.assertIn("START unit=fast-facts routes=highways",text); self.assertIn("CACHE HIT routes=highways",text)
            report=json.loads((cache/"last_run.json").read_text(encoding="utf-8")); self.assertEqual(report["status"],"DONE"); self.assertEqual(report["blocks"]["highways"]["status"],"CACHE HIT")

    def test_long_source_passes_have_progress_contract(self):
        fast=(TOOLS/"fast_osm_facts.py").read_text(encoding="utf-8"); area=(TOOLS/"area_source_cache.py").read_text(encoding="utf-8")
        self.assertIn("PROGRESS_SECONDS = 10.0",fast); self.assertIn("[fast-facts] nodes=",fast)
        self.assertIn("PROGRESS_INTERVAL_S = 10.0",area); self.assertIn("[area-facts] records=",area)

if __name__=="__main__": unittest.main()
