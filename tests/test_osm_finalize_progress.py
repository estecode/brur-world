"""Verify timestamped source-cache status reporting and persistent diagnostics."""

from __future__ import annotations

import contextlib
import hashlib
import io
import json
import re
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
from osm_source_cache import build_source_caches  # noqa: E402

FIXTURE = '''<?xml version="1.0" encoding="UTF-8"?><osm version="0.6"><node id="1" lon="18" lat="59.3"/><node id="2" lon="18.001" lat="59.3"/><way id="10"><nd ref="1"/><nd ref="2"/><tag k="highway" v="residential"/></way></osm>'''


class Copy(osmium.SimpleHandler):
    def __init__(self, writer): super().__init__(); self.writer = writer
    def node(self, value): self.writer.add_node(value)
    def way(self, value): self.writer.add_way(value)
    def relation(self, value): self.writer.add_relation(value)


def write_pbf(xml, pbf):
    with osmium.SimpleWriter(str(pbf), overwrite=True) as writer:
        Copy(writer).apply_file(str(xml))


def fake_extract(source: Path, cache_dir: Path, route: str) -> dict:
    destination = cache_dir / f"{route}.osm.pbf"
    shutil.copyfile(source, destination)
    digest = hashlib.sha256(destination.read_bytes()).hexdigest()
    return {
        "domain": route, "pyrosm_version": "test", "records": 1,
        "counts": {"records": 1}, "sha256": digest,
        "extract_seconds": 0.01, "write_seconds": 0.01,
        "checksum_seconds": 0.01, "elapsed_seconds": 0.03,
        "peak_rss_bytes": 1024,
    }


class Tests(unittest.TestCase):
    def test_status_has_timestamp_plan_cache_hit_and_persistent_report(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); xml = root / "f.osm"; xml.write_text(FIXTURE, encoding="utf-8")
            pbf = root / "f.osm.pbf"; write_pbf(xml, pbf); cache = root / "cache"
            output = io.StringIO()
            with mock.patch("osm_source_cache._run_extractor", side_effect=fake_extract), contextlib.redirect_stdout(output):
                build_source_caches(pbf, cache, ("highways",))
                build_source_caches(pbf, cache, ("highways",))
            text = output.getvalue()
            self.assertRegex(text, r"\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}\] \[osm-source\]")
            self.assertIn("PLAN route=highways status=REBUILD", text)
            self.assertIn("CACHE HIT routes=highways", text)
            report = json.loads((cache / "last_run.json").read_text(encoding="utf-8"))
            self.assertEqual(report["status"], "DONE")
            self.assertEqual(report["blocks"]["highways"]["status"], "CACHE HIT")

    def test_long_extractor_has_periodic_heartbeat_contract(self):
        self.assertGreater(osm_source_cache.HEARTBEAT_SECONDS, 0)
        text = (TOOLS / "osm_source_cache.py").read_text(encoding="utf-8")
        self.assertIn("PROGRESS route=", text)
        self.assertIn("timeout=HEARTBEAT_SECONDS", text)
        self.assertIn("ERROR route=", text)


if __name__ == "__main__": unittest.main()
