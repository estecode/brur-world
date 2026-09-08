"""Automatic tests for deterministic offline GPS address/POI search."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from build_search_index import load_named_pois
from gps_search import SearchIndex, SearchRecord, load_search_index, normalize_search_text, write_search_index


class GpsSearchTests(unittest.TestCase):
    def setUp(self) -> None:
        self.records = [
            SearchRecord("address:node:1", "address", "Storgatan 10", 10.0, 20.0, "Malmö"),
            SearchRecord("poi:node:2", "poi", "City Garaget", 30.0, 40.0, "garage"),
            SearchRecord("poi:node:3", "poi", "City Garaget", 50.0, 60.0, "Lund"),
            SearchRecord("poi:node:4", "poi", "Södersjukhuset", 70.0, 80.0, "hospital"),
        ]
        self.index = SearchIndex(self.records)

    def test_normalization_is_case_and_diacritic_insensitive(self) -> None:
        self.assertEqual(normalize_search_text("SÖDERSJUKHUSET"), "sodersjukhuset")
        self.assertEqual(self.index.search("södersjukhuset")[0].record_id, "poi:node:4")

    def test_prefix_and_partial_tokens_are_ranked_deterministically(self) -> None:
        first = self.index.search("city gar")
        second = self.index.search("CITY GAR")
        self.assertEqual([item.record_id for item in first], [item.record_id for item in second])
        self.assertEqual([item.record_id for item in first], ["poi:node:2", "poi:node:3"])

    def test_address_search_finds_known_address(self) -> None:
        result = self.index.search("storgatan 10")
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0].kind, "address")
        self.assertEqual((result[0].x, result[0].y), (10.0, 20.0))

    def test_duplicate_names_remain_distinct_and_disambiguated(self) -> None:
        result = self.index.search("city garaget")
        self.assertEqual(len(result), 2)
        self.assertNotEqual(result[0].record_id, result[1].record_id)
        self.assertEqual({item.subtitle for item in result}, {"garage", "Lund"})

    def test_serialization_round_trip_preserves_search_facts(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "search_index.jsonl"
            write_search_index(self.records, path)
            loaded = load_search_index(path)
            self.assertEqual(
                [(item.record_id, item.display_text, item.x, item.y) for item in loaded.search("city")],
                [(item.record_id, item.display_text, item.x, item.y) for item in self.index.search("city")],
            )

    def test_search_is_independent_of_runtime_marker_visibility(self) -> None:
        # No visibility/filter field is part of SearchRecord: searchable source facts survive
        # regardless of whether a later map-marker policy would currently render the POI.
        self.assertEqual(self.index.search("city")[0].display_text, "City Garaget")

    def test_named_imported_pois_become_search_records(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "pois.jsonl"
            rows = [
                {"osm_type": "node", "osm_id": 7, "x": 1.0, "y": 2.0, "tags": {"name": "Test Sjukhus", "amenity": "hospital"}},
                {"osm_type": "node", "osm_id": 8, "x": 3.0, "y": 4.0, "tags": {"amenity": "parking"}},
            ]
            path.write_text("".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8")
            records = load_named_pois(path)
            self.assertEqual(len(records), 1)
            self.assertEqual(records[0].record_id, "poi:node:7")
            self.assertEqual(SearchIndex(records).search("test sjukhus")[0].record_id, "poi:node:7")


if __name__ == "__main__":
    unittest.main()
