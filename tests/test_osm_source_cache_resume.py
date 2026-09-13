"""Verify bounded route-writer handles and fail-closed resumable OSM source spools."""

from __future__ import annotations

import io
import pickle
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock
from xml.etree import ElementTree

import osmium

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from osm_source_cache import (  # noqa: E402
    MAX_OPEN_NODE_BUCKETS,
    NODE_RECORD,
    SPOOL_DIR_NAME,
    SPOOL_MARKER_NAME,
    SourceCacheHandler,
    _RouteWriter,
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


def write_pbf(source: Path, destination: Path) -> None:
    with osmium.SimpleWriter(str(destination), overwrite=True) as writer:
        FixtureCopyHandler(writer).apply_file(str(source))


class OsmSourceCacheResumeTests(unittest.TestCase):
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

    def test_route_writer_bounds_open_node_bucket_handles(self) -> None:
        work = self.root / "writer-work"
        work.mkdir()
        writer = _RouteWriter("highways", work, self.root / "highways.osm")
        try:
            for bucket in range(MAX_OPEN_NODE_BUCKETS + 6):
                writer.add_node(bucket, 18.0 + bucket * 0.001, 59.3)
                self.assertLessEqual(len(writer.bucket_handles), MAX_OPEN_NODE_BUCKETS)
        finally:
            writer.close_inputs()

    def test_route_writer_uses_compact_binary_for_untagged_way_nodes(self) -> None:
        work = self.root / "compact-work"
        work.mkdir()
        writer = _RouteWriter("areas", work, self.root / "areas.osm")
        count = 4_096
        try:
            for node_id in range(count):
                writer.add_node(node_id, 18.0 + node_id * 0.000001, 59.3)
        finally:
            writer.close_inputs()

        route_dir = work / "route-areas"
        compact_size = sum(path.stat().st_size for path in route_dir.glob("nodes-*.bin"))
        self.assertEqual(compact_size, count * NODE_RECORD.size)
        self.assertFalse(any(route_dir.glob("nodes-??.pkl")))

        legacy = io.BytesIO()
        for node_id in range(count):
            pickle.dump((node_id, 18.0 + node_id * 0.000001, 59.3, {}), legacy, protocol=5)
        self.assertLess(compact_size, len(legacy.getvalue()) * 0.6)

    def test_tagged_node_overrides_duplicate_compact_node_on_publish(self) -> None:
        work = self.root / "tagged-work"
        work.mkdir()
        destination = self.root / "pois.osm"
        writer = _RouteWriter("pois", work, destination)
        writer.add_node(7, 18.0, 59.3)
        writer.add_node(7, 18.1, 59.4, {"amenity": "cafe"})
        counts = writer.publish()

        root = ElementTree.parse(destination).getroot()
        nodes = root.findall("node")
        self.assertEqual(len(nodes), 1)
        self.assertEqual(nodes[0].attrib["id"], "7")
        self.assertEqual(nodes[0].attrib["lon"], repr(18.1))
        self.assertEqual(nodes[0].find("tag").attrib, {"k": "amenity", "v": "cafe"})
        self.assertEqual(counts["nodes"], 1)

    def test_finalization_failure_resumes_completed_spool_without_source_scan(self) -> None:
        with mock.patch.object(_RouteWriter, "publish", side_effect=RuntimeError("synthetic finalization failure")):
            with self.assertRaisesRegex(RuntimeError, "synthetic finalization failure"):
                build_source_caches(self.pbf, self.cache, ("highways",))

        spool = self.cache / SPOOL_DIR_NAME
        self.assertTrue((spool / SPOOL_MARKER_NAME).is_file())

        with mock.patch.object(SourceCacheHandler, "apply_file", side_effect=AssertionError("unexpected source rescan")):
            caches = build_source_caches(self.pbf, self.cache, ("highways",))

        self.assertTrue(caches["highways"].is_file())
        self.assertFalse(spool.exists())

    def test_source_mismatch_rejects_completed_spool_and_rescans(self) -> None:
        with mock.patch.object(_RouteWriter, "publish", side_effect=RuntimeError("synthetic finalization failure")):
            with self.assertRaises(RuntimeError):
                build_source_caches(self.pbf, self.cache, ("highways",))

        self.source.write_text(FIXTURE.replace("residential", "service"), encoding="utf-8")
        self.pbf.unlink()
        write_pbf(self.source, self.pbf)

        original = SourceCacheHandler.apply_file
        calls = 0

        def counted(handler, filename, *args, **kwargs):
            nonlocal calls
            calls += 1
            return original(handler, filename, *args, **kwargs)

        with mock.patch.object(SourceCacheHandler, "apply_file", counted):
            build_source_caches(self.pbf, self.cache, ("highways",))
        self.assertEqual(calls, 1)

    def test_partial_spool_without_completion_marker_is_never_reused(self) -> None:
        spool = self.cache / SPOOL_DIR_NAME
        spool.mkdir(parents=True)
        (spool / "ways.pkl").write_bytes(b"partial")

        original = SourceCacheHandler.apply_file
        calls = 0

        def counted(handler, filename, *args, **kwargs):
            nonlocal calls
            calls += 1
            return original(handler, filename, *args, **kwargs)

        with mock.patch.object(SourceCacheHandler, "apply_file", counted):
            build_source_caches(self.pbf, self.cache, ("highways",))
        self.assertEqual(calls, 1)
        self.assertFalse(spool.exists())


if __name__ == "__main__":
    unittest.main()
