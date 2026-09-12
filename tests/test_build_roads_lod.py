"""Regression tests for the offline road LOD policy."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
sys.path.insert(0, str(TOOLS))
spec = importlib.util.spec_from_file_location("build_roads", TOOLS / "build_roads.py")
assert spec is not None and spec.loader is not None
build_roads = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_roads)


class RoadLodBuildPolicyTest(unittest.TestCase):
    def test_road_hierarchy_gains_detail_toward_near_lod(self) -> None:
        self.assertEqual(build_roads.LOD_MAX_CLASS, (4, 5, 6))
        self.assertLessEqual(build_roads.LOD_MAX_CLASS[0], build_roads.LOD_MAX_CLASS[1])
        self.assertLessEqual(build_roads.LOD_MAX_CLASS[1], build_roads.LOD_MAX_CLASS[2])

    def test_geometry_simplification_decreases_toward_near_lod(self) -> None:
        self.assertEqual(build_roads.LOD_MIN_SPACING, (1200.0, 300.0, 0.0))
        self.assertGreater(build_roads.LOD_MIN_SPACING[0], build_roads.LOD_MIN_SPACING[1])
        self.assertGreater(build_roads.LOD_MIN_SPACING[1], build_roads.LOD_MIN_SPACING[2])

    def test_thinning_keeps_endpoints_and_reduces_far_geometry(self) -> None:
        points = [(float(x), 0.0) for x in range(0, 3001, 100)]
        far = build_roads.thin(points, build_roads.LOD_MIN_SPACING[0])
        medium = build_roads.thin(points, build_roads.LOD_MIN_SPACING[1])
        near = build_roads.thin(points, build_roads.LOD_MIN_SPACING[2])
        self.assertEqual(far[0], points[0])
        self.assertEqual(far[-1], points[-1])
        self.assertLess(len(far), len(medium))
        self.assertLess(len(medium), len(near))
        self.assertEqual(near, points)


if __name__ == "__main__":
    unittest.main()
