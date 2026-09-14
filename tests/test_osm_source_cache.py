"""Verify BOSC3 semantic source-cache ownership and cache-first reuse."""

from __future__ import annotations

import hashlib
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import osmium

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from osm_source_cache import ALL_ROUTES, CACHE_FORMAT, ROUTE_VERSIONS, build_source_caches  # noqa: E402
from tests.test_pyrosm_extract import Tests as PyrosmExtractTests  # noqa: E402,F401

FIXTURE = """<?xml version="1.0" encoding="UTF-8"?>
<osm version="0.6">
  <node id="1" lon="18.0000" lat="59.3000"><tag k="highway" v="traffic_signals"/></node>
  <node id="2" lon="18.0010" lat="59.3000"/>
  <node id="3" lon="18.0020" lat="59.3000"><tag k="amenity" v="school"/><tag k="name" v="Fixture School"/></node>
  <node id="4" lon="18.0030" lat="59.3000"><tag k="addr:housenumber" v="12"/><tag k="addr:street" v="Testvägen"/></node>
  <way id="10"><nd ref="1"/><nd ref="2"/><tag k="highway" v="residential"/></way>
  <way id="20"><nd ref="1"/><nd ref="2"/><tag k="building" v="yes"/></way>
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


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Tests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.root = Path(self.temp.name)
        xml = self.root / "fixture.osm"; xml.write_text(FIXTURE, encoding="utf-8")
        self.pbf = self.root / "fixture.osm.pbf"; write_pbf(xml, self.pbf)
        self.cache = self.root / "cache"

    def tearDown(self): self.temp.cleanup()

    def fake_extract(self, source: Path, cache_dir: Path, route: str) -> dict:
        destination = cache_dir / f"{route}.osm.pbf"
        shutil.copyfile(source, destination)
        return {
            "domain": route,
            "pyrosm_version": "test",
            "records": 1,
            "counts": {"records": 1},
            "size_bytes": destination.stat().st_size,
            "sha256": digest(destination),
            "extract_seconds": 0.01,
            "write_seconds": 0.01,
            "checksum_seconds": 0.01,
            "elapsed_seconds": 0.03,
            "peak_rss_bytes": 1024,
        }

    def test_all_semantic_blocks_publish_versioned_checksummed_manifest(self):
        with mock.patch("osm_source_cache._run_extractor", side_effect=self.fake_extract):
            outputs = build_source_caches(self.pbf, self.cache, ALL_ROUTES)
        self.assertEqual(set(outputs), set(ALL_ROUTES))
        manifest = json.loads((self.cache / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["format"], CACHE_FORMAT)
        for route in ALL_ROUTES:
            entry = manifest["routes"][route]
            self.assertTrue(entry["complete"])
            self.assertEqual(entry["version"], ROUTE_VERSIONS[route])
            self.assertEqual(entry["extractor"], "pyrosm")
            self.assertEqual(len(entry["sha256"]), 64)
            self.assertEqual(entry["file"], f"{route}.osm.pbf")
            self.assertTrue(outputs[route].is_file())

    def test_selective_request_builds_only_requested_block(self):
        calls: list[str] = []
        def extract(source, cache_dir, route):
            calls.append(route); return self.fake_extract(source, cache_dir, route)
        with mock.patch("osm_source_cache._run_extractor", side_effect=extract):
            outputs = build_source_caches(self.pbf, self.cache, ("traffic_signals",))
        self.assertEqual(calls, ["traffic_signals"])
        self.assertEqual(set(outputs), {"traffic_signals"})
        self.assertTrue((self.cache / "traffic_signals.osm.pbf").is_file())
        self.assertFalse((self.cache / "buildings.osm.pbf").exists())

    def test_valid_cache_never_calls_extractor_again(self):
        with mock.patch("osm_source_cache._run_extractor", side_effect=self.fake_extract):
            build_source_caches(self.pbf, self.cache, ("highways",))
        with mock.patch("osm_source_cache._run_extractor", side_effect=AssertionError("unexpected PBF extraction")):
            reused = build_source_caches(self.pbf, self.cache, ("highways",))
        self.assertTrue(reused["highways"].is_file())

    def test_unknown_route_fails_closed(self):
        with self.assertRaises(ValueError):
            build_source_caches(self.pbf, self.cache, ("not-a-domain",))


if __name__ == "__main__": unittest.main()
