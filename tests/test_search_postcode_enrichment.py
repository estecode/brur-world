"""Input/output tests for deterministic offline address postcode enrichment."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from build_search_index import PostcodeSample, infer_nearby_postcode, infer_postcode


class SearchPostcodeEnrichmentTests(unittest.TestCase):
    def test_infers_unique_postcode_for_same_street_and_locality(self) -> None:
        known = {("kungsljusgatan", "dalby"): {"24756"}}
        self.assertEqual(infer_postcode("Kungsljusgatan", "Dalby", known), "24756")

    def test_refuses_ambiguous_street_locality(self) -> None:
        known = {("storgatan", "lund"): {"22220", "22350"}}
        self.assertEqual(infer_postcode("Storgatan", "Lund", known), "")

    def test_does_not_infer_without_locality(self) -> None:
        known = {("kungsljusgatan", "dalby"): {"24756"}}
        self.assertEqual(infer_postcode("Kungsljusgatan", "", known), "")

    def test_infers_nearby_postcode_when_same_locality_samples_agree(self) -> None:
        grid = {
            (0, 0): [
                PostcodeSample("24756", "dalby", 20.0, 20.0),
                PostcodeSample("24756", "dalby", 40.0, 30.0),
                PostcodeSample("24756", "dalby", 60.0, 35.0),
            ]
        }
        self.assertEqual(infer_nearby_postcode(0.0, 0.0, "Dalby", grid), "24756")

    def test_nearby_inference_refuses_conflicting_postcodes(self) -> None:
        grid = {
            (0, 0): [
                PostcodeSample("24756", "dalby", 20.0, 20.0),
                PostcodeSample("24750", "dalby", 40.0, 30.0),
            ]
        }
        self.assertEqual(infer_nearby_postcode(0.0, 0.0, "Dalby", grid), "")

    def test_nearby_inference_ignores_other_localities(self) -> None:
        grid = {
            (0, 0): [
                PostcodeSample("24756", "lund", 20.0, 20.0),
                PostcodeSample("24756", "lund", 40.0, 30.0),
            ]
        }
        self.assertEqual(infer_nearby_postcode(0.0, 0.0, "Dalby", grid), "")


if __name__ == "__main__":
    unittest.main()
