"""Tests the #126 self-contained Windows client bundle packager."""

from __future__ import annotations

import json
import struct
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from package_world_showcase_client import package_client  # noqa: E402
from prepare_world_showcase import CITY_CENTERS, MAP_MAGIC, MAP_TRIANGLE  # noqa: E402


class WorldShowcaseClientPackageTests(unittest.TestCase):
    def test_bundle_contains_binary_and_only_derived_runtime_subset(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "world_data"
            source.mkdir()
            (source / "manifest.json").write_text(json.dumps({"tile_size": 32000.0}), encoding="utf-8")

            records = []
            for index, (_city, (x, y)) in enumerate(CITY_CENTERS.items()):
                records.append({
                    "id": f"way/{index}",
                    "x": x,
                    "y": y,
                    "geometry": [{"outer": [[x, y], [x + 10, y], [x + 10, y + 10]], "holes": []}],
                    "tags": {"building": "yes"},
                })
            (source / "buildings.jsonl").write_text(
                "\n".join(json.dumps(record) for record in records) + "\n",
                encoding="utf-8",
            )

            with (source / "background.brmap").open("wb") as handle:
                handle.write(MAP_MAGIC)
                handle.write(struct.pack("<I", len(CITY_CENTERS)))
                for index, (_city, (x, y)) in enumerate(CITY_CENTERS.items()):
                    handle.write(MAP_TRIANGLE.pack(index % 5, x, y, x + 50.0, y, x, y + 50.0))

            binaries = root / "binary"
            binaries.mkdir()
            (binaries / "brur.exe").write_bytes(b"exe")
            (binaries / "brur.pck").write_bytes(b"pck")
            (binaries / "build_info.json").write_text(json.dumps({
                "pr": 128,
                "commit": "abcdef1234567890",
                "godot": "4.7.2.stable",
                "platform": "windows-x86_64",
            }), encoding="utf-8")

            output = root / "client.zip"
            info = package_client(binaries, source, output)
            self.assertEqual(info["commit"], "abcdef1234567890")
            self.assertFalse(info["runtime_source_rebuilt"])

            with zipfile.ZipFile(output) as archive:
                names = set(archive.namelist())
                self.assertIn("BRUR/brur.exe", names)
                self.assertIn("BRUR/brur.pck", names)
                self.assertIn("BRUR/build_info.json", names)
                self.assertIn("BRUR/client_bundle_info.json", names)
                self.assertIn("BRUR/runtime_data/showcase_manifest.json", names)
                for city in CITY_CENTERS:
                    self.assertIn(f"BRUR/runtime_data/background_{city}.brmap", names)
                self.assertNotIn("BRUR/runtime_data/buildings.jsonl", names)
                self.assertNotIn("BRUR/runtime_data/background.brmap", names)


if __name__ == "__main__":
    unittest.main()
