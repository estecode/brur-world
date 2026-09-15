"""Exercise normalized source facts through the actual offline target builders."""
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

from build_features import build_buildings, build_pois
from build_roads import build_roads
from build_routing_dataset import build_routing_dataset
from build_search_binary import build_search_binary
from build_search_index import build_search_index
from build_traffic_signals_sources import build_traffic_signals_sources
from osm_source_cache import build_source_caches

FIXTURE = """<?xml version="1.0" encoding="UTF-8"?>
<osm version="0.6">
  <node id="1" lon="18.0000" lat="59.3000"><tag k="highway" v="traffic_signals"/></node>
  <node id="2" lon="18.0010" lat="59.3000"/>
  <node id="3" lon="18.0020" lat="59.3000"><tag k="amenity" v="school"/><tag k="name" v="Fixture School"/></node>
  <node id="4" lon="18.0030" lat="59.3000"><tag k="addr:housenumber" v="12"/><tag k="addr:street" v="Testvägen"/><tag k="addr:city" v="Lund"/></node>
  <node id="5" lon="18.0000" lat="59.3010"/>
  <node id="6" lon="18.0010" lat="59.3010"/>
  <way id="10"><nd ref="1"/><nd ref="2"/><tag k="highway" v="residential"/><tag k="maxspeed" v="50"/></way>
  <way id="20"><nd ref="1"/><nd ref="2"/><nd ref="6"/><nd ref="5"/><nd ref="1"/><tag k="building" v="yes"/><tag k="building:levels" v="2"/></way>
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
    def test_real_builders_consume_normalized_fact_blocks_without_pbf_reparse(self):
        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            xml = root / "fixture.osm"; xml.write_text(FIXTURE, encoding="utf-8")
            pbf = root / "fixture.osm.pbf"; write_pbf(xml, pbf)
            cache = root / "cache"
            world = root / "world"
            sources = build_source_caches(
                pbf,
                cache,
                ("highways", "traffic_signals", "pois", "addresses", "areas"),
            )

            build_roads(sources["highways"], world)
            self.assertTrue(any((world / "lod2").glob("*.brtile")))

            routing = build_routing_dataset(sources["highways"], world)
            self.assertGreater(routing["node_count"], 0)
            self.assertTrue((world / "routing.brg").is_file())
            self.assertTrue((world / "routing_snap.brs").is_file())

            traffic = build_traffic_signals_sources(sources["traffic_signals"], sources["highways"], world)
            self.assertGreaterEqual(traffic["exported_signal_count"], 1)

            build_pois(sources["pois"], world, sources["areas"])
            self.assertTrue((world / "pois.jsonl").is_file())

            buildings = build_buildings(sources["areas"], world)
            self.assertGreaterEqual(buildings["features"]["buildings"], 1)

            search_jsonl = build_search_index(sources["addresses"], world)
            build_search_binary(search_jsonl, world / "search_index.bsi")
            self.assertTrue((world / "search_index.bsi").is_file())


if __name__ == "__main__":
    unittest.main()
