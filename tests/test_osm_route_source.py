"""Guard real-data callers behind the shared normalized source-cache adapter."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT=Path(__file__).resolve().parents[1]; TOOLS=ROOT/"tools"
if str(TOOLS) not in sys.path: sys.path.insert(0,str(TOOLS))

import osm_route_source

class OsmRouteSourceTests(unittest.TestCase):
    def test_authoritative_pbf_is_resolved_through_requested_route_cache(self)->None:
        with tempfile.TemporaryDirectory() as temp_name:
            root=Path(temp_name); source=root/"sweden-test.osm.pbf"; source.write_bytes(b"fixture"); output=root/"world_data"; cached=output/"osm_source_cache"/"highways.brfacts"
            with mock.patch.object(osm_route_source,"build_source_caches",return_value={"highways":cached}) as build:
                resolved=osm_route_source.resolve_route_source(source,output,"highways")
            self.assertEqual(resolved,cached); build.assert_called_once_with(source,output/"osm_source_cache",("highways",))

    def test_normalized_cache_and_small_fixture_sources_are_not_recached(self)->None:
        with tempfile.TemporaryDirectory() as temp_name:
            root=Path(temp_name); output=root/"world_data"; cache=output/"osm_source_cache"; cache.mkdir(parents=True)
            for source in (root/"fixture.osm", cache/"highways.brfacts", cache/"areas.baf"):
                source.touch()
                with mock.patch.object(osm_route_source,"build_source_caches",side_effect=AssertionError("unexpected cache build")):
                    self.assertEqual(osm_route_source.resolve_route_source(source,output,"highways"),source)

    def test_non_cache_pbf_still_uses_authoritative_cache_boundary(self)->None:
        with tempfile.TemporaryDirectory() as temp_name:
            root=Path(temp_name); source=root/"highways.osm.pbf"; source.touch(); output=root/"world_data"; cached=output/"osm_source_cache"/"highways.brfacts"
            with mock.patch.object(osm_route_source,"build_source_caches",return_value={"highways":cached}) as build:
                self.assertEqual(osm_route_source.resolve_route_source(source,output,"highways"),cached)
            build.assert_called_once()

    def test_builders_have_normalized_fact_paths(self)->None:
        routing=(TOOLS/"build_routing_dataset.py").read_text(encoding="utf-8"); roads=(TOOLS/"build_roads.py").read_text(encoding="utf-8")
        self.assertIn("build_routing_facts",routing); self.assertIn("iter_highway_ways",roads)

if __name__=="__main__": unittest.main()
