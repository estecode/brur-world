"""Tests deterministic prebuilt building render chunks and their cache contract.

Dependencies:
- Uses tools/build_building_mesh_pyramid.py with temporary authoritative buildings.jsonl input.
- Does not require Sweden PBF or Godot.
"""

from __future__ import annotations

import hashlib
import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from build_building_mesh_pyramid import (  # noqa: E402
    FORMAT_VERSION,
    HEADER_STRUCT,
    LOD_LEVELS,
    MAGIC,
    VERTEX_STRUCT,
    build_building_mesh_pyramid,
    building_mesh_pyramid_cache_valid,
    footprint_area_m2,
    triangulate_ring,
)


class BuildingMeshPyramidTests(unittest.TestCase):
    def _record(self, source_id: str, x: float, y: float, size: float) -> dict:
        half = size * 0.5
        return {
            "id": source_id,
            "x": x,
            "y": y,
            "geometry": [
                {
                    "outer": [
                        [x - half, y - half],
                        [x + half, y - half],
                        [x + half, y + half],
                        [x - half, y + half],
                    ],
                    "holes": [],
                }
            ],
            "tags": {"building": "yes", "building:levels": "4"},
        }

    def _make_world(self, directory: str) -> Path:
        world = Path(directory) / "world_data"
        world.mkdir()
        records = [
            self._record("small", 100.0, 100.0, 10.0),
            self._record("medium", 300.0, 100.0, 20.0),
            self._record("large", 500.0, 100.0, 40.0),
            self._record("huge", 700.0, 100.0, 70.0),
        ]
        (world / "manifest.json").write_text(
            json.dumps({"origin_x": 0.0, "origin_y": 0.0, "features": {"buildings": len(records)}}),
            encoding="utf-8",
        )
        (world / "buildings.jsonl").write_text(
            "\n".join(json.dumps(record, separators=(",", ":")) for record in records) + "\n",
            encoding="utf-8",
        )
        return world

    def _payload_hashes(self, world: Path) -> dict[str, str]:
        root = world / "building_mesh_lod"
        return {
            str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(root.glob("lod*/*.bmc"))
        }

    def test_pyramid_is_deterministic_progressive_and_manifested(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            world = self._make_world(directory)
            report = build_building_mesh_pyramid(world)

            self.assertEqual(report["format_version"], FORMAT_VERSION)
            self.assertEqual([item["buildings"] for item in report["levels"]], [1, 2, 3, 4])
            self.assertEqual(
                [item["chunk_size_m"] for item in report["levels"]],
                [level.chunk_size_m for level in LOD_LEVELS],
            )
            self.assertTrue(
                all(not level.simplified for level in LOD_LEVELS),
                "LOD changes building selection only; footprint silhouettes stay authoritative at every level",
            )
            for level in LOD_LEVELS:
                files = list((world / "building_mesh_lod" / f"lod{level.lod}").glob("*.bmc"))
                self.assertTrue(files, f"lod{level.lod} emits at least one render chunk")
                payload = files[0].read_bytes()
                magic, version, vertices = HEADER_STRUCT.unpack_from(payload, 0)
                self.assertEqual(magic, MAGIC)
                self.assertEqual(version, FORMAT_VERSION)
                self.assertGreater(vertices, 0)
                self.assertEqual(len(payload), HEADER_STRUCT.size + vertices * VERTEX_STRUCT.size)

            manifest = json.loads((world / "manifest.json").read_text(encoding="utf-8"))
            features = manifest["features"]
            self.assertEqual(features["building_mesh_lod_dir"], "building_mesh_lod")
            self.assertEqual(features["building_mesh_lod_format_version"], FORMAT_VERSION)
            self.assertEqual(len(features["building_mesh_lod_levels"]), 4)
            self.assertTrue(all(not item["simplified"] for item in features["building_mesh_lod_levels"]))
            self.assertTrue(building_mesh_pyramid_cache_valid(world))

            first_hashes = self._payload_hashes(world)
            build_building_mesh_pyramid(world)
            self.assertEqual(first_hashes, self._payload_hashes(world))
            self.assertTrue(building_mesh_pyramid_cache_valid(world))

    def test_cache_fails_closed_when_source_changes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            world = self._make_world(directory)
            build_building_mesh_pyramid(world)
            source = world / "buildings.jsonl"
            source.write_text(
                source.read_text(encoding="utf-8") + json.dumps(self._record("new", 900.0, 100.0, 30.0)) + "\n",
                encoding="utf-8",
            )
            self.assertFalse(building_mesh_pyramid_cache_valid(world))

    def test_area_and_concave_triangulation_are_stable(self) -> None:
        record = self._record("square", 0.0, 0.0, 20.0)
        self.assertEqual(footprint_area_m2(record), 400.0)
        concave = [(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (2.0, 2.0), (0.0, 4.0)]
        triangles = triangulate_ring(concave)
        self.assertEqual(len(triangles), 3)
        self.assertEqual(triangles, triangulate_ring(list(concave)))


if __name__ == "__main__":
    unittest.main()