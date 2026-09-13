"""Guard real-data road/routing callers behind the shared OSM route-cache adapter."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import osm_route_source  # noqa: E402


class OsmRouteSourceTests(unittest.TestCase):
    def test_authoritative_pbf_is_resolved_through_requested_route_cache(self) -> None:
        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            source = root / "sweden-test.osm.pbf"
            source.write_bytes(b"fixture")
            output = root / "world_data"
            cached = output / "osm_source_cache" / "highways.osm"
            with mock.patch.object(
                osm_route_source,
                "build_source_caches",
                return_value={"highways": cached},
            ) as build:
                resolved = osm_route_source.resolve_route_source(source, output, "highways")
            self.assertEqual(resolved, cached)
            build.assert_called_once_with(source, output / "osm_source_cache", ("highways",))

    def test_route_cache_and_small_fixture_sources_are_not_recached(self) -> None:
        with tempfile.TemporaryDirectory() as temp_name:
            root = Path(temp_name)
            output = root / "world_data"
            for source in (root / "fixture.osm", root / "highways.osm"):
                with mock.patch.object(
                    osm_route_source,
                    "build_source_caches",
                    side_effect=AssertionError("unexpected cache build"),
                ):
                    self.assertEqual(osm_route_source.resolve_route_source(source, output, "highways"), source)

    def test_real_data_road_and_routing_builders_use_highway_adapter(self) -> None:
        routing = (TOOLS / "build_routing_dataset.py").read_text(encoding="utf-8")
        roads = (TOOLS / "build_roads.py").read_text(encoding="utf-8")
        self.assertIn('resolve_route_source(source, output, "highways")', routing)
        self.assertIn('resolve_route_source(source, output, "highways")', roads)


if __name__ == "__main__":
    unittest.main()
