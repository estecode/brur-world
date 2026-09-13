"""Verify single-pass OSM source ingest, route selection, and fail-closed cache reuse."""

from __future__ import annotations

import io
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

from build_background import build_background  # noqa: E402
from build_features import build_buildings, build_pois  # noqa: E402
from build_roads import build_roads  # noqa: E402
from build_routing_dataset import build_routing_dataset  # noqa: E402
from build_search_index import build_search_index  # noqa: E402
from build_traffic_signals import build_traffic_signals  # noqa: E402
from osm_source_cache import (  # noqa: E402
    ALL_ROUTES,
    ROUTE_VERSIONS,
    SourceCacheHandler,
    _ProgressDisplay,
    build_source_caches,
)


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
    <nd ref=\"5\"/><nd ref=\"6\"/><nd ref=\"7\"/><nd ref=\"8\"/><nd ref=\"5\"/>
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


class FixtureCopyHandler(osmium.SimpleHandler):
    def __init__(self, writer: osmium.SimpleWriter) -> None:
        super().__init__()
        self.writer = writer

    def node(self, node) -> None:
        self.writer.add_node(node)

    def way(self, way) -> None:
        self.writer.add_way(way)

    def relation(self, relation) -> None:
        self.writer.add_relation(relation)


class TTYBuffer(io.StringIO):
    def isatty(self) -> bool:
        return True


def write_pbf(source: Path, destination: Path) -> None:
    with osmium.SimpleWriter(str(destination), overwrite=True) as writer:
        FixtureCopyHandler(writer).apply_file(str(source))


def ids(path: Path, tag: str) -> set[int]:
    root = ET.parse(path).getroot()
    return {int(element.attrib["id"]) for element in root.findall(tag)}


class OsmSourceCacheTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source = self.root / "fixture.osm"
        self.source.write_text(FIXTURE, encoding="utf-8")
        self.pbf = self.root / "fixture.osm.pbf"
        write_pbf(self.source, self.pbf)
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
            caches = build_source_caches(self.pbf, self.cache, ALL_ROUTES)

        self.assertEqual(calls, [str(self.pbf)])
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

    def test_live_route_counters_follow_source_matches(self) -> None:
        stream = io.StringIO()
        display = _ProgressDisplay(self.pbf, {"digest": "abc123"}, ALL_ROUTES, {}, stream)
        work_dir = self.root / "progress-work"
        work_dir.mkdir()
        handler = SourceCacheHandler(work_dir, set(ALL_ROUTES), {}, display)
        try:
            handler.apply_file(str(self.pbf), locations=True)
        finally:
            handler.close()
        self.assertEqual(
            display.route_counts,
            {"addresses": 2, "areas": 3, "highways": 1, "pois": 2, "traffic_signals": 2},
        )
        self.assertEqual(handler.counts, {"nodes": 8, "ways": 5, "relations": 1})

    def test_tty_progress_rewrites_compact_block_with_hash_and_total(self) -> None:
        stream = TTYBuffer()
        display = _ProgressDisplay(
            Path("/tmp/sweden-260824.osm.pbf"),
            {"digest": "abc123"},
            ("highways", "traffic_signals"),
            {"nodes": 8, "ways": 5, "relations": 1},
            stream,
        )
        display.hit("highways")
        display.hit("traffic_signals")
        display.render({"nodes": 10, "ways": 2, "relations": 1}, 1.0)
        display.hit("highways")
        display.render({"nodes": 10, "ways": 3, "relations": 1}, 2.0)
        output = stream.getvalue()
        self.assertIn("source: sweden-260824.osm.pbf", output)
        self.assertIn("sha256: abc123", output)
        self.assertIn("scanned: 13 / 14 items", output)
        self.assertIn("scanned: 14 / 14 items", output)
        self.assertIn("highways", output)
        self.assertIn("traffic_signals", output)
        self.assertIn("\x1b[", output)

    def test_non_tty_progress_is_log_friendly_without_ansi(self) -> None:
        stream = io.StringIO()
        display = _ProgressDisplay(Path("sweden.osm.pbf"), {"digest": "abc123"}, ("pois",), {}, stream)
        display.hit("pois")
        display.render({"nodes": 5, "ways": 1, "relations": 0}, 1.0)
        output = stream.getvalue()
        self.assertIn("scanned: 6 items", output)
        self.assertIn("pois=1", output)
        self.assertNotIn("\x1b[", output)

    def test_routes_are_independently_selectable(self) -> None:
        caches = build_source_caches(self.pbf, self.cache, ("highways", "addresses"))
        self.assertEqual(set(caches), {"highways", "addresses"})
        self.assertTrue((self.cache / "highways.osm").is_file())
        self.assertTrue((self.cache / "addresses.osm").is_file())
        self.assertFalse((self.cache / "areas.osm").exists())
        self.assertFalse((self.cache / "pois.osm").exists())

    def test_valid_same_source_cache_does_not_rescan(self) -> None:
        build_source_caches(self.pbf, self.cache, ("highways", "pois"))
        with mock.patch.object(SourceCacheHandler, "apply_file", side_effect=AssertionError("unexpected source scan")):
            reused = build_source_caches(self.pbf, self.cache, ("highways", "pois"))
        self.assertEqual(set(reused), {"highways", "pois"})

    def test_missing_route_file_fails_closed_and_rebuilds_once(self) -> None:
        build_source_caches(self.pbf, self.cache, ("highways", "addresses"))
        (self.cache / "addresses.osm").unlink()
        original = SourceCacheHandler.apply_file
        calls = 0

        def counted(handler, filename, *args, **kwargs):
            nonlocal calls
            calls += 1
            return original(handler, filename, *args, **kwargs)

        with mock.patch.object(SourceCacheHandler, "apply_file", counted):
            build_source_caches(self.pbf, self.cache, ("highways", "addresses"))
        self.assertEqual(calls, 1)
        self.assertTrue((self.cache / "addresses.osm").is_file())

    def test_route_version_invalidates_only_that_route(self) -> None:
        build_source_caches(self.pbf, self.cache, ("highways", "addresses"))
        highway_before = (self.cache / "highways.osm").stat().st_mtime_ns
        original_version = ROUTE_VERSIONS["addresses"]
        try:
            ROUTE_VERSIONS["addresses"] = original_version + 1
            build_source_caches(self.pbf, self.cache, ("highways", "addresses"))
        finally:
            ROUTE_VERSIONS["addresses"] = original_version
        self.assertEqual((self.cache / "highways.osm").stat().st_mtime_ns, highway_before)
        manifest = json.loads((self.cache / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["routes"]["addresses"]["version"], original_version + 1)

    def test_changed_source_invalidates_requested_routes(self) -> None:
        build_source_caches(self.pbf, self.cache, ("highways",))
        before = json.loads((self.cache / "manifest.json").read_text(encoding="utf-8"))["source"]
        self.source.write_text(FIXTURE.replace('name\" v=\"Signal Street', 'name\" v=\"Changed Street'), encoding="utf-8")
        self.pbf.unlink()
        write_pbf(self.source, self.pbf)
        build_source_caches(self.pbf, self.cache, ("highways",))
        after = json.loads((self.cache / "manifest.json").read_text(encoding="utf-8"))["source"]
        self.assertNotEqual(before, after)

    def test_generated_route_caches_feed_existing_builders(self) -> None:
        caches = build_source_caches(self.pbf, self.cache, ALL_ROUTES)
        output = self.root / "world"
        build_roads(caches["highways"], output)
        build_routing_dataset(caches["highways"], output)
        build_traffic_signals(caches["traffic_signals"], output)
        build_background(caches["areas"], output)
        build_pois(caches["pois"], output)
        build_buildings(caches["areas"], output)
        search_path = build_search_index(caches["addresses"], output)

        self.assertTrue((output / "routing.brg").is_file())
        self.assertTrue((output / "routing_geometry.brh").is_file())
        self.assertTrue((output / "traffic_signals.json").is_file())
        self.assertTrue((output / "buildings.jsonl").is_file())
        self.assertGreater((output / "buildings.jsonl").stat().st_size, 0)
        self.assertTrue((output / "pois.jsonl").is_file())
        self.assertTrue(search_path.is_file())
        self.assertGreater(search_path.stat().st_size, 0)

    def test_unknown_route_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            build_source_caches(self.pbf, self.cache, ("does-not-exist",))


if __name__ == "__main__":
    unittest.main()
