"""Regression for GeoPackage relation POIs in #220."""
from __future__ import annotations

import io
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from build_features import _consume_poi_facts
from normalized_source_facts import FactWriter


class _Tiles:
    def __init__(self) -> None:
        self.records: list[dict] = []

    def write(self, record: dict) -> None:
        self.records.append(record)


class Tests(unittest.TestCase):
    def test_relation_facts_are_left_for_shared_area_cache(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            source = Path(temp) / "pois.brfacts"
            writer = FactWriter(source, 1)
            writer.write({"osm_type": "node", "osm_id": 1, "x": 1.0, "y": 2.0, "tags": {"amenity": "cafe"}})
            writer.write({"osm_type": "way", "osm_id": 2, "x": 3.0, "y": 4.0, "tags": {"shop": "yes"}})
            writer.write({"osm_type": "relation", "osm_id": 3, "x": 5.0, "y": 6.0, "tags": {"tourism": "museum"}})
            writer.publish()

            output = io.StringIO()
            tiles = _Tiles()
            nodes, ways = _consume_poi_facts(source, output, tiles)

            self.assertEqual((nodes, ways), (1, 1))
            self.assertEqual([record["osm_type"] for record in tiles.records], ["node", "way"])
            self.assertNotIn('"osm_type":"relation"', output.getvalue())


if __name__ == "__main__":
    unittest.main()
