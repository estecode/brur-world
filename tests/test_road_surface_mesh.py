"""Deterministic acceptance tests for the offline connected road-surface mesher."""

from __future__ import annotations

from pathlib import Path
import sys
import tempfile
import unittest

from shapely.geometry import Point

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
sys.path.insert(0, str(TOOLS))

from road_surface_mesh import (  # noqa: E402
    MITER_LIMIT,
    ROAD_WIDTHS_M,
    SEAM_QUANTUM_M,
    RoadSurfaceAccumulator,
    SurfaceWay,
    duplicate_triangle_area,
    grade_from_tags,
)


class RoadSurfaceMeshTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tile_size = 100.0

    def test_same_level_overlap_has_one_deterministic_owner(self) -> None:
        acc = RoadSurfaceAccumulator(self.tile_size)
        acc.add_way(SurfaceWay(((-40.0, 0.0), (40.0, 0.0)), 0, 0))
        acc.add_way(SurfaceWay(((0.0, -40.0), (0.0, 40.0)), 5, 0))
        resolved = acc.resolve_tile((-1, -1)) + acc.resolve_tile((0, -1)) + acc.resolve_tile((-1, 0)) + acc.resolve_tile((0, 0))
        motorway = [geometry for road_class, grade, geometry in resolved if road_class == 0 and grade == 0]
        residential = [geometry for road_class, grade, geometry in resolved if road_class == 5 and grade == 0]
        self.assertTrue(motorway)
        self.assertTrue(residential)
        for high in motorway:
            for low in residential:
                self.assertLessEqual(high.intersection(low).area, 1.0e-6)
        records = []
        for tile in acc.tile_keys():
            records.extend(acc.triangles_for_tile(tile))
        self.assertLessEqual(duplicate_triangle_area(records), 1.0e-9)

    def test_bent_polyline_is_one_connected_surface(self) -> None:
        acc = RoadSurfaceAccumulator(1000.0)
        acc.add_way(SurfaceWay(((10.0, 10.0), (50.0, 10.0), (70.0, 40.0)), 4, 0))
        resolved = acc.resolve_tile((0, 0))
        self.assertEqual(len(resolved), 1)
        geometry = resolved[0][2]
        self.assertEqual(geometry.geom_type, "Polygon")
        self.assertTrue(geometry.buffer(1.0e-6).contains(Point(50.0, 10.0)))
        self.assertGreater(len(acc.triangles_for_tile((0, 0))), 2)

    def test_acute_angle_miter_is_bounded(self) -> None:
        acc = RoadSurfaceAccumulator(1000.0)
        points = ((100.0, 100.0), (200.0, 100.0), (105.0, 110.0))
        acc.add_way(SurfaceWay(points, 4, 0))
        geometry = acc.resolve_tile((0, 0))[0][2]
        min_x, min_y, max_x, max_y = geometry.bounds
        width = ROAD_WIDTHS_M[4]
        self.assertLess(max_x - min_x, 120.0 + width * MITER_LIMIT)
        self.assertLess(max_y - min_y, 30.0 + width * MITER_LIMIT)

    def test_three_and_four_way_junctions_are_coherent(self) -> None:
        for branches in (3, 4):
            acc = RoadSurfaceAccumulator(1000.0)
            acc.add_way(SurfaceWay(((500.0, 500.0), (560.0, 500.0)), 3, 0))
            acc.add_way(SurfaceWay(((500.0, 500.0), (440.0, 500.0)), 3, 0))
            acc.add_way(SurfaceWay(((500.0, 500.0), (500.0, 560.0)), 3, 0))
            if branches == 4:
                acc.add_way(SurfaceWay(((500.0, 500.0), (500.0, 440.0)), 3, 0))
            resolved = acc.resolve_tile((0, 0))
            self.assertEqual(len(resolved), 1)
            self.assertEqual(resolved[0][2].geom_type, "Polygon")
            self.assertTrue(resolved[0][2].contains(Point(500.0, 500.0)))
            self.assertGreater(len(acc.triangles_for_tile((0, 0))), branches)

    def test_grade_separated_roads_are_not_unioned(self) -> None:
        acc = RoadSurfaceAccumulator(1000.0)
        acc.add_way(SurfaceWay(((100.0, 500.0), (900.0, 500.0)), 2, 0))
        acc.add_way(SurfaceWay(((500.0, 100.0), (500.0, 900.0)), 2, 1))
        resolved = acc.resolve_tile((0, 0))
        self.assertEqual({grade for _road_class, grade, _geometry in resolved}, {0, 1})
        ground = next(geometry for _road_class, grade, geometry in resolved if grade == 0)
        bridge = next(geometry for _road_class, grade, geometry in resolved if grade == 1)
        self.assertGreater(ground.intersection(bridge).area, 0.0)
        self.assertEqual(grade_from_tags({"bridge": "yes"}), 1)
        self.assertEqual(grade_from_tags({"tunnel": "yes"}), -1)
        self.assertEqual(grade_from_tags({"layer": "3"}), 3)

    def test_tile_seam_vertices_match_after_quantization(self) -> None:
        acc = RoadSurfaceAccumulator(self.tile_size)
        acc.add_way(SurfaceWay(((20.0, 40.0), (180.0, 60.0)), 5, 0))
        left = acc.triangles_for_tile((0, 0))
        right = acc.triangles_for_tile((1, 0))
        left_y = sorted({round(y, 6) for _c, _g, tri in left for x, y in tri if abs(x - self.tile_size) <= SEAM_QUANTUM_M})
        right_y = sorted({round(y, 6) for _c, _g, tri in right for x, y in tri if abs(x) <= SEAM_QUANTUM_M})
        self.assertTrue(left_y)
        self.assertEqual(left_y, right_y)

    def test_output_triangles_are_valid_and_serializable(self) -> None:
        acc = RoadSurfaceAccumulator(1000.0)
        acc.add_way(SurfaceWay(((100.0, 100.0), (400.0, 300.0), (800.0, 250.0)), 5, 0))
        records = acc.triangles_for_tile((0, 0))
        self.assertTrue(records)
        for _road_class, _grade, triangle in records:
            (ax, ay), (bx, by), (cx, cy) = triangle
            area2 = abs((bx - ax) * (cy - ay) - (by - ay) * (cx - ax))
            self.assertGreater(area2, 1.0e-8)
        with tempfile.TemporaryDirectory() as temp_dir:
            stats = acc.write(Path(temp_dir))
            self.assertEqual(stats["tiles"], 1)
            self.assertEqual(stats["triangles"], len(records))
            self.assertGreater(stats["bytes"], 8)


if __name__ == "__main__":
    unittest.main()
