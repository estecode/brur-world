"""Tests the #126 disposable multi-city cache built from existing runtime data."""

from __future__ import annotations

import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from prepare_world_showcase import (  # noqa: E402
    BACKGROUND_RADIUS_M,
    CITY_CENTERS,
    DEFAULT_RADIUS_M,
    MAP_MAGIC,
    MAP_TRIANGLE,
    prepare,
)


class WorldShowcasePrepareTests(unittest.TestCase):
    def test_default_working_sets_are_local(self) -> None:
        self.assertLessEqual(DEFAULT_RADIUS_M, 1500.0)
        self.assertGreaterEqual(DEFAULT_RADIUS_M, 1000.0)
        self.assertLessEqual(BACKGROUND_RADIUS_M, 50000.0)

    def test_prepare_selects_all_showcase_cities_without_rebuild(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "world_data"
            source.mkdir()
            (source / "manifest.json").write_text(json.dumps({"tile_size": 32000.0}), encoding="utf-8")

            records = []
            for index, (_city, (x, y)) in enumerate(CITY_CENTERS.items()):
                records.append(
                    {
                        "id": f"way/{index}",
                        "x": x + 25.0,
                        "y": y - 25.0,
                        "geometry": [{"outer": [[x, y], [x + 10, y], [x + 10, y + 10]], "holes": []}],
                        "tags": {"building": "yes"},
                    }
                )
            records.append({"id": "far", "x": 0.0, "y": 0.0, "geometry": [], "tags": {"building": "yes"}})
            (source / "buildings.jsonl").write_text(
                "\n".join(json.dumps(record) for record in records) + "\n",
                encoding="utf-8",
            )

            triangles = []
            for index, (_city, (x, y)) in enumerate(CITY_CENTERS.items()):
                triangles.append(MAP_TRIANGLE.pack(index % 5, x, y, x + 50.0, y, x, y + 50.0))
            triangles.append(MAP_TRIANGLE.pack(0, 0.0, 0.0, 50.0, 0.0, 0.0, 50.0))
            with (source / "background.brmap").open("wb") as handle:
                handle.write(MAP_MAGIC)
                handle.write(struct.pack("<I", len(triangles)))
                for triangle in triangles:
                    handle.write(triangle)

            output = root / "cache"
            report = prepare(source, output, radius_m=500.0, background_radius_m=1000.0)

            self.assertIs(report["source_rebuilt"], False)
            self.assertEqual(report["selected_records"], 3)
            self.assertGreaterEqual(report["tile_count"], 3)
            self.assertEqual(set(report["selected_by_city"]), set(CITY_CENTERS))
            self.assertTrue(all(count == 1 for count in report["selected_by_city"].values()))
            self.assertTrue(all(count == 1 for count in report["background_triangles_by_city"].values()))
            for city in CITY_CENTERS:
                path = output / f"background_{city}.brmap"
                self.assertTrue(path.is_file())
                self.assertLess(path.stat().st_size, (source / "background.brmap").stat().st_size)
            self.assertTrue((output / "showcase_manifest.json").is_file())


if __name__ == "__main__":
    unittest.main()
