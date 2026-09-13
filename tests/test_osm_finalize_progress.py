"""Verify live route-cache finalization progress without extra source traversal."""

from __future__ import annotations

import contextlib
import io
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

from osm_source_cache import (  # noqa: E402
    SourceCacheHandler,
    _FinalizeProgressDisplay,
    build_source_caches,
)


FIXTURE = """<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<osm version=\"0.6\">
  <node id=\"1\" lon=\"18.0000\" lat=\"59.3000\"/>
  <node id=\"2\" lon=\"18.0010\" lat=\"59.3000\"/>
  <way id=\"10\">
    <nd ref=\"1\"/><nd ref=\"2\"/>
    <tag k=\"highway\" v=\"residential\"/>
  </way>
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


class OsmFinalizeProgressTests(unittest.TestCase):
    def test_tty_finalization_progress_rewrites_compact_block(self) -> None:
        stream = TTYBuffer()
        progress = _FinalizeProgressDisplay(("highways", "areas"), stream=stream, interval=1)
        progress.render(force=True)
        progress.select("highways")
        progress.record()
        progress.select("areas", 2)
        progress.record()
        progress.set_phase("publishing highways")

        output = stream.getvalue()
        self.assertIn("route-cache finalization", output)
        self.assertIn("spool records: 2", output)
        self.assertIn("highways", output)
        self.assertIn("areas", output)
        self.assertIn("publishing highways", output)
        self.assertIn("\x1b[", output)

    def test_real_finalization_reports_progress_without_second_source_scan(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "fixture.osm"
            source.write_text(FIXTURE, encoding="utf-8")
            pbf = root / "fixture.osm.pbf"
            write_pbf(source, pbf)
            cache = root / "cache"

            original = SourceCacheHandler.apply_file
            calls = 0

            def counted(handler, filename, *args, **kwargs):
                nonlocal calls
                calls += 1
                return original(handler, filename, *args, **kwargs)

            output = io.StringIO()
            with mock.patch.object(SourceCacheHandler, "apply_file", counted):
                with contextlib.redirect_stdout(output):
                    build_source_caches(pbf, cache, ("highways",))

            text = output.getvalue()
            self.assertEqual(calls, 1)
            self.assertIn("finalizing: selecting spool records", text)
            self.assertIn("spool records: 1", text)
            self.assertIn("routes: highways=1", text)
            self.assertIn("finalizing: publishing highways", text)
            self.assertIn("finalizing: complete", text)
            self.assertNotIn("\x1b[", text)


if __name__ == "__main__":
    unittest.main()
