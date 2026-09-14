"""Verify BOSC2 direct route fan-out, assembled area facts and cache reuse."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from unittest import mock

import osmium

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from area_source_cache import AreaFactHandler, iter_area_facts  # noqa: E402
from build_background import build_background  # noqa: E402
from build_features import build_buildings, build_pois  # noqa: E402
from build_roads import build_roads  # noqa: E402
from build_routing_dataset import build_routing_dataset  # noqa: E402
from build_search_index import build_search_index  # noqa: E402
from build_traffic_signals import build_traffic_signals  # noqa: E402
from osm_source_cache import ALL_ROUTES, ROUTE_VERSIONS, SourceCacheHandler, build_source_caches  # noqa: E402

FIXTURE = """<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<osm version=\"0.6\">
  <node id=\"1\" lon=\"18.0000\" lat=\"59.3000\"><tag k=\"highway\" v=\"traffic_signals\"/></node>
  <node id=\"2\" lon=\"18.0010\" lat=\"59.3000\"/>
  <node id=\"3\" lon=\"18.0020\" lat=\"59.3000\"><tag k=\"amenity\" v=\"school\"/><tag k=\"name\" v=\"Fixture School\"/></node>
  <node id=\"4\" lon=\"18.0030\" lat=\"59.3000\"><tag k=\"addr:housenumber\" v=\"12\"/><tag k=\"addr:street\" v=\"Testvägen\"/></node>
  <node id=\"5\" lon=\"18.0100\" lat=\"59.3100\"/>
  <node id=\"6\" lon=\"18.0110\" lat=\"59.3100\"/>
  <node id=\"7\" lon=\"18.0110\" lat=\"59.3110\"/>
  <node id=\"8\" lon=\"18.0100\" lat=\"59.3110\"/>
  <node id=\"9\" lon=\"18.0200\" lat=\"59.3000\"/>
  <node id=\"10\" lon=\"18.0200\" lat=\"59.3200\"/>
  <way id=\"10\"><nd ref=\"1\"/><nd ref=\"2\"/><tag k=\"highway\" v=\"residential\"/><tag k=\"name\" v=\"Signal Street\"/></way>
  <way id=\"20\"><nd ref=\"2\"/><nd ref=\"3\"/><tag k=\"amenity\" v=\"parking\"/></way>
  <way id=\"30\"><nd ref=\"5\"/><nd ref=\"6\"/><nd ref=\"7\"/><nd ref=\"8\"/><nd ref=\"5\"/><tag k=\"building\" v=\"yes\"/></way>
  <way id=\"40\"><nd ref=\"5\"/><nd ref=\"6\"/><nd ref=\"7\"/><nd ref=\"8\"/><nd ref=\"5\"/></way>
  <way id=\"50\"><nd ref=\"2\"/><nd ref=\"4\"/><tag k=\"addr:housenumber\" v=\"14\"/><tag k=\"addr:street\" v=\"Testvägen\"/></way>
  <way id=\"60\"><nd ref=\"9\"/><nd ref=\"10\"/><tag k=\"natural\" v=\"coastline\"/></way>
  <relation id=\"100\"><member type=\"way\" ref=\"40\" role=\"outer\"/><tag k=\"type\" v=\"multipolygon\"/><tag k=\"building\" v=\"yes\"/><tag k=\"amenity\" v=\"library\"/></relation>
</osm>
"""


class FixtureCopyHandler(osmium.SimpleHandler):
    def __init__(self, writer: osmium.SimpleWriter) -> None:
        super().__init__(); self.writer = writer
    def node(self, node) -> None: self.writer.add_node(node)
    def way(self, way) -> None: self.writer.add_way(way)
    def relation(self, relation) -> None: self.writer.add_relation(relation)


def write_pbf(source: Path, destination: Path) -> None:
    with osmium.SimpleWriter(str(destination), overwrite=True) as writer:
        FixtureCopyHandler(writer).apply_file(str(source))


def ids(path: Path, tag: str) -> set[int]:
    root = ET.parse(path).getroot()
    return {int(element.attrib["id"]) for element in root.findall(tag)}


class OsmSourceCacheTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(); self.root = Path(self.temp.name)
        self.source = self.root / "fixture.osm"; self.source.write_text(FIXTURE, encoding="utf-8")
        self.pbf = self.root / "fixture.osm.pbf"; write_pbf(self.source, self.pbf)
        self.cache = self.root / "cache"
    def tearDown(self) -> None: self.temp.cleanup()

    def test_fast_routes_one_scan_and_areas_separate_libosmium_pass(self) -> None:
        fast_calls = 0; area_calls = 0
        original_fast = SourceCacheHandler.apply_file; original_area = AreaFactHandler.apply_file
        def counted_fast(handler, filename, *args, **kwargs):
            nonlocal fast_calls; fast_calls += 1; return original_fast(handler, filename, *args, **kwargs)
        def counted_area(handler, filename, *args, **kwargs):
            nonlocal area_calls; area_calls += 1; return original_area(handler, filename, *args, **kwargs)
        with mock.patch.object(SourceCacheHandler, "apply_file", counted_fast), mock.patch.object(AreaFactHandler, "apply_file", counted_area):
            caches = build_source_caches(self.pbf, self.cache, ALL_ROUTES)
        self.assertEqual(fast_calls, 1); self.assertEqual(area_calls, 1)
        self.assertIn(10, ids(caches["highways"], "way"))
        self.assertIn(1, ids(caches["traffic_signals"], "node"))
        self.assertIn(20, ids(caches["pois"], "way"))
        self.assertIn(50, ids(caches["addresses"], "way"))
        facts = list(iter_area_facts(caches["areas"]))
        self.assertTrue(any(f["tags"].get("building") == "yes" for f in facts))
        self.assertTrue(any(f["osm_type"] == "relation" and f["tags"].get("amenity") == "library" for f in facts))
        coastline = next(f for f in facts if f.get("geometry_type") == "coastline")
        self.assertEqual(coastline["osm_id"], 60)
        self.assertEqual(coastline["tags"], {"natural": "coastline"})
        self.assertEqual(len(coastline["geometry"]), 2)
        manifest = json.loads((self.cache / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["format"], "BOSC2")
        for route in ALL_ROUTES:
            self.assertTrue(manifest["routes"][route]["complete"])
            self.assertEqual(manifest["routes"][route]["version"], ROUTE_VERSIONS[route])

    def test_no_pickle_hot_path_exists(self) -> None:
        text = (TOOLS / "osm_source_cache.py").read_text(encoding="utf-8") + (TOOLS / "area_source_cache.py").read_text(encoding="utf-8")
        self.assertNotIn("import pickle", text)
        self.assertNotIn("ways.pkl", text)

    def test_valid_same_source_cache_does_not_rescan_or_rehash(self) -> None:
        build_source_caches(self.pbf, self.cache, ("highways", "areas"))
        with mock.patch.object(SourceCacheHandler, "apply_file", side_effect=AssertionError("unexpected fast scan")), mock.patch.object(AreaFactHandler, "apply_file", side_effect=AssertionError("unexpected area scan")):
            reused = build_source_caches(self.pbf, self.cache, ("highways", "areas"))
        self.assertEqual(set(reused), {"highways", "areas"})

    def test_route_version_invalidates_only_that_route(self) -> None:
        build_source_caches(self.pbf, self.cache, ("highways", "addresses"))
        highway_before = (self.cache / "highways.osm").stat().st_mtime_ns
        original = ROUTE_VERSIONS["addresses"]
        try:
            ROUTE_VERSIONS["addresses"] = original + 1
            build_source_caches(self.pbf, self.cache, ("highways", "addresses"))
        finally:
            ROUTE_VERSIONS["addresses"] = original
        self.assertEqual((self.cache / "highways.osm").stat().st_mtime_ns, highway_before)

    def test_generated_caches_feed_existing_builders(self) -> None:
        caches = build_source_caches(self.pbf, self.cache, ALL_ROUTES)
        output = self.root / "world"
        build_roads(caches["highways"], output)
        build_routing_dataset(caches["highways"], output)
        build_traffic_signals(caches["traffic_signals"], output)
        build_background(caches["areas"], output)
        build_pois(caches["pois"], output, caches["areas"])
        build_buildings(caches["areas"], output)
        search_path = build_search_index(caches["addresses"], output)
        self.assertTrue((output / "routing.brg").is_file())
        self.assertTrue((output / "background.brmap").is_file())
        self.assertGreater((output / "buildings.jsonl").stat().st_size, 0)
        self.assertGreater(search_path.stat().st_size, 0)
        features = json.loads((output / "manifest.json").read_text(encoding="utf-8"))["features"]
        self.assertTrue(features["way_pois_complete"])
        self.assertTrue(features["relation_pois_complete"])
        self.assertEqual(features["poi_areas"], 1)
        self.assertTrue(features["area_source_shared"])

    def test_unknown_route_is_rejected(self) -> None:
        with self.assertRaises(ValueError): build_source_caches(self.pbf, self.cache, ("does-not-exist",))


if __name__ == "__main__": unittest.main()
