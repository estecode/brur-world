"""Input/output tests for deterministic offline address postcode enrichment."""

from __future__ import annotations

import unittest

from tools.build_search_index import infer_postcode


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


if __name__ == "__main__":
    unittest.main()
