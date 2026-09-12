"""Verify single-pass OSM source ingest, route selection, and fail-closed cache reuse."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

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
  <way id=\"10\">
    <nd ref=\"1\"/><nd ref=\"2\"/>
    <tag k=\"highway\" v=\"residential\"/>
    <tag k=\"name\" v=\"Signal Street\"/>
  </way>
  <way id=\"20\">
    <nd ref=\"2\"/><nd ref=\"3\"/>
    <tag k=\"amenity\" v=\"parking\"/>
  </way>
  <way id=\"30\">
    <nd ref=\"5\"/><nd ref=\"6\"/><nd ref=\"7\"/><nd ref=\"8\"/><nd ref=\"5\"/>
    <tag k=\"building\" v=\"yes\"/>
  </way>
  <way id=\"40\">
    <nd ref=\"6\"/><nd ref=\"7\"/>
  </way>
  <way id=\"50\">
    <nd ref=\"2\"/><nd ref=\"4\"/>
    <tag k=\"addr:housenumber\" v=\"14\"/><tag k=\"addr:street\" v=\"Testvägen\"/>
  </way>
  <relation id=\"100\">
    <member type=\"way\" ref=\"40\" role=\"outer\"/>
    <tag k=\"type\" v=\"multipolygon\"/>
    <tag k=\"building\" v=\"yes\"/>
  </relation>
</osm>
"""


def ids(path: Path, tag: str) -> set[int]:
    root = ET.parse(path).getroot()
    return {int(element.attrib["id"]) for element in root.findall(tag)}


class OsmSourceCacheTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source = self.root / "fixture.osm"
        self.source.write_text(FIXTURE, encoding="utf-8")
        self.cache = self.root / "cache"

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_all_routes_share_one_source_traversal(self) -> None:
        original = SourceCacheHandler.apply_file
        calls: list[str] = []

        def counted(handler, filename, *args, **kwargs):
            calls.append(str(filename))
            return original(handler, filename, *args, **kwargs)

        with mock.patch.object(SourceCacheHandler, "apply_file", counted):
            caches = build_source_caches(self.source, self.cache, ALL_ROUTES)

        self.assertEqual(calls, [str(self.source)])
        self.assertEqual(set(caches), set(ALL_ROUTES))
        self.assertIn(10, ids(caches["highways"], "way"))
        self.assertIn(1, ids(caches["traffic_signals"], "node"))
        self.assertIn(10, ids(caches["traffic_signals"], "way"))
        self.assertIn(3, ids(caches["pois"], "node"))
        self.assertIn(20, ids(caches["pois"], "way"))
        self.assertIn(4, ids(caches["addresses"], "node"))
        self.assertIn(50, ids(caches["addresses"], "way"))
        self.assertIn(30, ids(caches["areas"], "way"))
        self.assertIn(40, ids(caches["areas"], "way"))
        self.assertIn(100, ids(caches["areas"], "relation"))

        manifest = json.loads((self.cache / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["format"], "BOSC1")
        self.assertEqual(manifest["source_scan"], {"nodes": 8, "ways": 5, "relations": 1})
        for route in ALL_ROUTES:
            self.assertTrue(manifest["routes"][route]["complete"])
            self.assertEqual(manifest["routes"][route]["version"], ROUTE_VERSIONS[route])

    def test_routes_are_independently_selectable(self) -> None:
        caches = build_source_caches(self.source, self.cache, ("highways", "addresses"))
        self.assertEqual(set(caches), {"highways", "addresses"})
        self.assertTrue((self.cache / "highways.osm").is_file())
        self.assertTrue((self.cache / "addresses.osm").is_file())
        self.assertFalse((self.cache / "areas.osm").exists())
        self.assertFalse((self.cache / "pois.osm").exists())

    def test_valid_same_source_cache_does_not_rescan(self) -> None:
        build_source_caches(self.source, self.cache, ("highways", "pois"))
        with mock.patch.object(SourceCacheHandler, "apply_file", side_effect=AssertionError("unexpected source scan")):
            reused = build_source_caches(self.source, self.cache, ("highways", "pois"))
        self.assertEqual(set(reused), {"highways", "pois"})

    def test_missing_route_file_fails_closed_and_rebuilds_once(self) -> None:
        build_source_caches(self.source, self.cache, ("highways", "addresses"))
        (self.cache / "addresses.osm").unlink()
        original = SourceCacheHandler.apply_file
        calls = 0

        def counted(handler, filename, *args, **kwargs):
            nonlocal calls
            calls += 1
            return original(handler, filename, *args, **kwargs)

        with mock.patch.object(SourceCacheHandler, "apply_file", counted):
            build_source_caches(self.source, self.cache, ("highways", "addresses"))
        self.assertEqual(calls, 1)
        self.assertTrue((self.cache / "addresses.osm").is_file())

    def test_route_version_invalidates_only_that_route(self) -> None:
        build_source_caches(self.source, self.cache, ("highways", "addresses"))
        highway_before = (self.cache / "highways.osm").stat().st_mtime_ns
        original_version = ROUTE_VERSIONS["addresses"]
        try:
            ROUTE_VERSIONS["addresses"] = original_version + 1
            build_source_caches(self.source, self.cache, ("highways", "addresses"))
        finally:
            ROUTE_VERSIONS["addresses"] = original_version
        self.assertEqual((self.cache / "highways.osm").stat().st_mtime_ns, highway_before)
        manifest = json.loads((self.cache / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["routes"]["addresses"]["version"], original_version + 1)

    def test_changed_source_invalidates_requested_routes(self) -> None:
        build_source_caches(self.source, self.cache, ("highways",))
        before = json.loads((self.cache / "manifest.json").read_text(encoding="utf-8"))["source"]
        self.source.write_text(FIXTURE.replace('name\" v=\"Signal Street', 'name\" v=\"Changed Street'), encoding="utf-8")
        build_source_caches(self.source, self.cache, ("highways",))
        after = json.loads((self.cache / "manifest.json").read_text(encoding="utf-8"))["source"]
        self.assertNotEqual(before, after)

    def test_unknown_route_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            build_source_caches(self.source, self.cache, ("does-not-exist",))


if __name__ == "__main__":
    unittest.main()
