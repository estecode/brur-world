"""Verify compact BAF2 relation assembly, holes and deterministic geometry decoding."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

import osmium

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from area_source_cache import MAGIC, VERSION, area_source_cache_metadata, build_area_source_cache, iter_area_facts

FIXTURE = """<?xml version="1.0" encoding="UTF-8"?>
<osm version="0.6">
  <node id="1" lon="18.0000" lat="59.3000"/>
  <node id="2" lon="18.0100" lat="59.3000"/>
  <node id="3" lon="18.0100" lat="59.3100"/>
  <node id="4" lon="18.0000" lat="59.3100"/>
  <node id="5" lon="18.0030" lat="59.3030"/>
  <node id="6" lon="18.0070" lat="59.3030"/>
  <node id="7" lon="18.0070" lat="59.3070"/>
  <node id="8" lon="18.0030" lat="59.3070"/>
  <way id="100"><nd ref="1"/><nd ref="2"/><nd ref="3"/><nd ref="4"/><nd ref="1"/></way>
  <way id="101"><nd ref="5"/><nd ref="6"/><nd ref="7"/><nd ref="8"/><nd ref="5"/></way>
  <relation id="200">
    <member type="way" ref="100" role="outer"/>
    <member type="way" ref="101" role="inner"/>
    <tag k="type" v="multipolygon"/>
    <tag k="building" v="yes"/>
    <tag k="name" v="Courtyard"/>
  </relation>
</osm>
"""


class Copy(osmium.SimpleHandler):
    def __init__(self, writer):
        super().__init__(); self.writer = writer
    def node(self, value): self.writer.add_node(value)
    def way(self, value): self.writer.add_way(value)
    def relation(self, value): self.writer.add_relation(value)


def write_pbf(xml: Path, pbf: Path) -> None:
    with osmium.SimpleWriter(str(pbf), overwrite=True) as writer:
        Copy(writer).apply_file(str(xml))


class Tests(unittest.TestCase):
    def test_relation_hole_is_assembled_once_and_round_trips_from_compact_cache(self):
        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            xml = root / "fixture.osm"; xml.write_text(FIXTURE, encoding="utf-8")
            pbf = root / "fixture.osm.pbf"; write_pbf(xml, pbf)
            cache = root / "areas.baf"
            report = build_area_source_cache(pbf, cache)
            self.assertGreater(report["records"], 0)
            self.assertEqual(cache.read_bytes()[:4], MAGIC)
            meta = area_source_cache_metadata(cache)
            self.assertEqual(meta["records"], report["records"])
            relations = [fact for fact in iter_area_facts(cache) if fact.get("osm_type") == "relation" and fact.get("osm_id") == 200]
            self.assertEqual(len(relations), 1)
            relation = relations[0]
            self.assertEqual(relation["tags"]["building"], "yes")
            self.assertEqual(len(relation["geometry"]), 1)
            self.assertEqual(len(relation["geometry"][0]["holes"]), 1)
            self.assertGreaterEqual(len(relation["geometry"][0]["outer"]), 4)
            self.assertGreaterEqual(len(relation["geometry"][0]["holes"][0]), 4)


if __name__ == "__main__":
    unittest.main()
