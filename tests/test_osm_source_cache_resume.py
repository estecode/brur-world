"""Verify BOSC3 checksum invalidation and fail-closed cache publication."""

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

import osm_source_cache  # noqa: E402
from osm_source_cache import ROUTE_VERSIONS, build_source_caches  # noqa: E402

FIXTURE = '''<?xml version="1.0" encoding="UTF-8"?><osm version="0.6">
<node id="1" lon="18" lat="59.3"/><node id="2" lon="18.001" lat="59.3"/>
<way id="10"><nd ref="1"/><nd ref="2"/><tag k="highway" v="residential"/></way></osm>'''


class Copy(osmium.SimpleHandler):
    def __init__(self, writer): super().__init__(); self.writer = writer
    def node(self, value): self.writer.add_node(value)
    def way(self, value): self.writer.add_way(value)
    def relation(self, value): self.writer.add_relation(value)


def write_pbf(xml: Path, pbf: Path) -> None:
    with osmium.SimpleWriter(str(pbf), overwrite=True) as writer:
        Copy(writer).apply_file(str(xml))


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Tests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.root = Path(self.temp.name)
        xml = self.root / "f.osm"; xml.write_text(FIXTURE, encoding="utf-8")
        self.pbf = self.root / "f.osm.pbf"; write_pbf(xml, self.pbf)
        self.cache = self.root / "cache"
        self.calls: list[str] = []

    def tearDown(self): self.temp.cleanup()

    def extract(self, source: Path, cache_dir: Path, route: str) -> dict:
        self.calls.append(route)
        destination = cache_dir / f"{route}.osm.pbf"
        shutil.copyfile(source, destination)
        return {
            "domain": route, "pyrosm_version": "test", "records": 1,
            "counts": {"records": 1}, "sha256": sha(destination),
            "extract_seconds": 0.01, "write_seconds": 0.01,
            "checksum_seconds": 0.01, "elapsed_seconds": 0.03,
            "peak_rss_bytes": 1024,
        }

    def test_changed_block_version_invalidates_only_that_block(self):
        with mock.patch("osm_source_cache._run_extractor", side_effect=self.extract):
            build_source_caches(self.pbf, self.cache, ("highways", "addresses"))
            self.calls.clear()
            original = ROUTE_VERSIONS["addresses"]
            try:
                ROUTE_VERSIONS["addresses"] = original + 1
                build_source_caches(self.pbf, self.cache, ("highways", "addresses"))
            finally:
                ROUTE_VERSIONS["addresses"] = original
        self.assertEqual(self.calls, ["addresses"])

    def test_tampered_cache_checksum_forces_only_that_block_rebuild(self):
        with mock.patch("osm_source_cache._run_extractor", side_effect=self.extract):
            build_source_caches(self.pbf, self.cache, ("highways", "addresses"))
            self.calls.clear()
            path = self.cache / "addresses.osm.pbf"
            path.write_bytes(path.read_bytes() + b"tamper")
            build_source_caches(self.pbf, self.cache, ("highways", "addresses"))
        self.assertEqual(self.calls, ["addresses"])

    def test_interrupted_extractor_never_marks_block_complete(self):
        def broken(source, cache_dir, route):
            (cache_dir / f"{route}.osm.pbf").write_bytes(b"partial")
            raise RuntimeError("boom")
        with mock.patch("osm_source_cache._run_extractor", side_effect=broken):
            with self.assertRaises(RuntimeError):
                build_source_caches(self.pbf, self.cache, ("highways",))
        manifest = self.cache / "manifest.json"
        if manifest.is_file():
            entry = json.loads(manifest.read_text(encoding="utf-8")).get("routes", {}).get("highways", {})
            self.assertIsNot(entry.get("complete"), True)
        run = json.loads((self.cache / "last_run.json").read_text(encoding="utf-8"))
        self.assertEqual(run["status"], "ERROR")
        self.assertEqual(run["blocks"]["highways"]["status"], "ERROR")

    def test_changed_authoritative_source_invalidates_requested_blocks(self):
        with mock.patch("osm_source_cache._run_extractor", side_effect=self.extract):
            build_source_caches(self.pbf, self.cache, ("highways", "addresses"))
            self.calls.clear()
            changed = self.root / "changed.osm"
            changed.write_text(FIXTURE.replace("residential", "service"), encoding="utf-8")
            self.pbf.unlink(); write_pbf(changed, self.pbf)
            build_source_caches(self.pbf, self.cache, ("highways", "addresses"))
        self.assertEqual(self.calls, ["highways", "addresses"])


if __name__ == "__main__": unittest.main()
