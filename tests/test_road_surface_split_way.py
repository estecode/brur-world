"""Regression coverage for OSM ways split at a shared bend node."""

from __future__ import annotations

from pathlib import Path
import sys
import unittest

from shapely.geometry import Point

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
sys.path.insert(0, str(TOOLS))

from road_surface_mesh import RoadSurfaceAccumulator, SurfaceWay, duplicate_triangle_area  # noqa: E402


class SplitWayRoadSurfaceTest(unittest.TestCase):
    def test_split_way_bend_has_no_triangular_wedge(self) -> None:
        """Two OSM ways continuing through one node must cover the whole join."""
        acc = RoadSurfaceAccumulator(1000.0)
        join = (500.0, 500.0)
        acc.add_way(SurfaceWay(((430.0, 500.0), join), 4, 0))
        acc.add_way(SurfaceWay((join, (555.0, 545.0)), 4, 0))

        resolved = acc.resolve_tile((0, 0))
        self.assertEqual(len(resolved), 1)
        geometry = resolved[0][2]
        self.assertEqual(geometry.geom_type, "Polygon")

        # A flat cap on each independently buffered OSM way leaves an uncovered
        # wedge on the outside of this bend. The healed surface must cover a small
        # disk around the shared physical road node instead.
        self.assertTrue(geometry.covers(Point(*join).buffer(2.5)))

        records = acc.triangles_for_tile((0, 0))
        self.assertTrue(records)
        self.assertLessEqual(duplicate_triangle_area(records), 1.0e-9)

    def test_different_classes_at_split_node_still_have_one_owner(self) -> None:
        acc = RoadSurfaceAccumulator(1000.0)
        join = (500.0, 500.0)
        acc.add_way(SurfaceWay(((430.0, 500.0), join), 2, 0))
        acc.add_way(SurfaceWay((join, (555.0, 545.0)), 5, 0))

        resolved = acc.resolve_tile((0, 0))
        high = next(geometry for road_class, grade, geometry in resolved if road_class == 2 and grade == 0)
        low = next(geometry for road_class, grade, geometry in resolved if road_class == 5 and grade == 0)
        self.assertLessEqual(high.intersection(low).area, 1.0e-6)
        self.assertTrue(high.union(low).covers(Point(*join).buffer(2.0)))


if __name__ == "__main__":
    unittest.main()
