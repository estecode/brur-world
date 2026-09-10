"""Tests that the #122 POC reuses existing building runtime data without rebuilding source datasets."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from prepare_building_poc import CITY_CENTERS, prepare  # noqa: E402


class BuildingPocPrepareTests(unittest.TestCase):
    def test_prepare_filters_existing_buildings_into_multi_city_tiles(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            tmp_path = Path(directory)
            source = tmp_path / "world_data"
            source.mkdir()
            (source / "manifest.json").write_text(json.dumps({"tile_size": 32000.0}), encoding="utf-8")

            records = []
            for index, (city, (x, y)) in enumerate(CITY_CENTERS.items(), start=1):
                records.append(
                    {
                        "id": index,
                        "x": x + 50.0,
                        "y": y - 50.0,
                        "geometry": [
                            {
                                "outer": [[x, y], [x + 10, y], [x + 10, y + 10]],
                                "holes": [],
                            }
                        ],
                        "tags": {"building": "yes", "name": city},
                    }
                )
            records.append(
                {
                    "id": 999,
                    "x": CITY_CENTERS["malmo"][0] + 50000.0,
                    "y": CITY_CENTERS["malmo"][1],
                    "geometry": [],
                    "tags": {"building": "yes"},
                }
            )
            (source / "buildings.jsonl").write_text(
                "".join(json.dumps(record) + "\n" for record in records),
                encoding="utf-8",
            )

            output = tmp_path / "cache"
            result = prepare(source, output, radius_m=1000.0)

            self.assertIs(result["source_rebuilt"], False)
            self.assertEqual(result["scanned_records"], 4)
            self.assertEqual(result["selected_records"], 3)
            self.assertGreaterEqual(result["tile_count"], 3)
            self.assertEqual(result["selected_by_city"], {"malmo": 1, "goteborg": 1, "stockholm": 1})
            cached_ids = set()
            for tile_file in output.glob("*.jsonl"):
                for line in tile_file.read_text(encoding="utf-8").splitlines():
                    cached_ids.add(json.loads(line)["id"])
            self.assertEqual(cached_ids, {1, 2, 3})


if __name__ == "__main__":
    unittest.main()
