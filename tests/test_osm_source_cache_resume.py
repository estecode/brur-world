"""Verify BOSC2 bounded staging and fail-closed atomic publication."""

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

from area_source_cache import area_source_cache_valid, build_area_source_cache  # noqa: E402
from osm_source_cache import MAX_OPEN_NODE_BUCKETS, NODE_RECORD, SourceCacheHandler, _RouteWriter, build_source_caches  # noqa: E402

FIXTURE = """<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<osm version=\"0.6\">
<node id=\"1\" lon=\"18.0\" lat=\"59.3\"/><node id=\"2\" lon=\"18.001\" lat=\"59.3\"/>
<node id=\"3\" lon=\"18.0\" lat=\"59.301\"/><node id=\"4\" lon=\"18.001\" lat=\"59.301\"/>
<way id=\"10\"><nd ref=\"1\"/><nd ref=\"2\"/><tag k=\"highway\" v=\"residential\"/></way>
<way id=\"20\"><nd ref=\"1\"/><nd ref=\"2\"/><nd ref=\"4\"/><nd ref=\"3\"/><nd ref=\"1\"/><tag k=\"building\" v=\"yes\"/></way>
</osm>"""

class Copy(osmium.SimpleHandler):
    def __init__(self, writer): super().__init__(); self.writer=writer
    def node(self, v): self.writer.add_node(v)
    def way(self, v): self.writer.add_way(v)
    def relation(self, v): self.writer.add_relation(v)

def write_pbf(xml: Path, pbf: Path) -> None:
    with osmium.SimpleWriter(str(pbf), overwrite=True) as writer: Copy(writer).apply_file(str(xml))

class Tests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.root=Path(self.temp.name)
        xml=self.root/"f.osm"; xml.write_text(FIXTURE, encoding="utf-8")
        self.pbf=self.root/"f.osm.pbf"; write_pbf(xml,self.pbf); self.cache=self.root/"cache"
    def tearDown(self): self.temp.cleanup()

    def test_route_writer_bounds_open_handles_and_uses_compact_nodes(self):
        work=self.root/"work"; work.mkdir(); writer=_RouteWriter("highways",work,self.root/"h.osm")
        count=4096
        try:
            for node_id in range(count):
                writer.add_node(node_id,18.0+node_id*1e-6,59.3)
                self.assertLessEqual(len(writer.bucket_handles),MAX_OPEN_NODE_BUCKETS)
        finally: writer.close_inputs()
        compact=sum(p.stat().st_size for p in (work/"route-highways").glob("nodes-*.bin"))
        self.assertEqual(compact,count*NODE_RECORD.size)
        self.assertFalse(any(work.rglob("*.pkl")))

    def test_interrupted_area_build_never_publishes_valid_cache(self):
        destination=self.root/"areas.baf"
        with mock.patch("area_source_cache.AreaFactHandler.apply_file", side_effect=RuntimeError("boom")):
            with self.assertRaises(RuntimeError): build_area_source_cache(self.pbf,destination)
        self.assertFalse(destination.exists()); self.assertFalse(area_source_cache_valid(destination))

    def test_truncated_area_cache_fails_closed(self):
        destination=self.root/"areas.baf"; build_area_source_cache(self.pbf,destination)
        self.assertTrue(area_source_cache_valid(destination))
        data=destination.read_bytes(); destination.write_bytes(data[:-3])
        self.assertFalse(area_source_cache_valid(destination))

    def test_failed_route_publish_does_not_mark_manifest_complete(self):
        original=_RouteWriter.publish
        with mock.patch.object(_RouteWriter,"publish",side_effect=RuntimeError("publish failed")):
            with self.assertRaises(RuntimeError): build_source_caches(self.pbf,self.cache,("highways",))
        manifest=self.cache/"manifest.json"
        if manifest.exists():
            entry=json.loads(manifest.read_text(encoding="utf-8")).get("routes",{}).get("highways",{})
            self.assertIsNot(entry.get("complete"),True)
        with mock.patch.object(_RouteWriter,"publish",original):
            built=build_source_caches(self.pbf,self.cache,("highways",))
        self.assertTrue(built["highways"].is_file())

    def test_changed_source_metadata_forces_source_scan(self):
        build_source_caches(self.pbf,self.cache,("highways",))
        original=SourceCacheHandler.apply_file; calls=0
        def counted(handler,filename,*args,**kwargs):
            nonlocal calls; calls+=1; return original(handler,filename,*args,**kwargs)
        # Rewriting a valid PBF changes strong metadata and exact digest.
        xml=self.root/"changed.osm"; xml.write_text(FIXTURE.replace("residential","service"),encoding="utf-8")
        self.pbf.unlink(); write_pbf(xml,self.pbf)
        with mock.patch.object(SourceCacheHandler,"apply_file",counted): build_source_caches(self.pbf,self.cache,("highways",))
        self.assertEqual(calls,1)

if __name__=="__main__": unittest.main()
