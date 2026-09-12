#!/usr/bin/env python3
"""Regression tests for expensive PR-check scope decisions.

Dependencies:
- Imports the project-owned tools/pr_check_scope.py policy.
- Uses representative changed-file sets only; no runtime/world data is required.
"""

from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from pr_check_scope import (  # noqa: E402
    building_tiles_required,
    city_light_real_data_required,
    native_gps_build_required,
    road_lod_rebuild_required,
    route_geometry_check_required,
    world_showcase_real_data_required,
)


BUILDING_UI_PR_FILES = (
    "scenes/main.tscn",
    "scripts/building_stream_layer.gd",
    "scripts/map_controls_ui.gd",
    "tests/godot/test_map_controls.gd",
    "tools/build_building_tiles.py",
)


def main() -> None:
    assert not route_geometry_check_required(BUILDING_UI_PR_FILES)
    assert not road_lod_rebuild_required(BUILDING_UI_PR_FILES), (
        "building/UI changes must not rebuild Sweden road LODs"
    )
    assert not native_gps_build_required(BUILDING_UI_PR_FILES), (
        "building/UI changes must not rebuild native GPS"
    )
    assert not city_light_real_data_required(BUILDING_UI_PR_FILES), (
        "building/UI changes must not rebuild city-light density"
    )
    assert not world_showcase_real_data_required(BUILDING_UI_PR_FILES), (
        "production building/UI changes must not prepare the old world showcase"
    )
    assert building_tiles_required(BUILDING_UI_PR_FILES), (
        "production building changes must prepare/reuse the building-tile runtime data"
    )

    for path in (
        "tools/build_routing.py",
        "tools/build_routing_dataset.py",
        "tools/check_route_geometry_dataset.py",
        "tools/route_geometry.py",
        "tools/world_common.py",
    ):
        assert route_geometry_check_required((path,)), f"routing owner must trigger scan: {path}"

    for path in (
        "tools/build_roads.py",
        "tools/build_sweden.py",
        "tools/world_common.py",
        "scripts/road_lod_policy.gd",
    ):
        assert road_lod_rebuild_required((path,)), f"road owner must trigger rebuild: {path}"

    assert native_gps_build_required(("native/gps_core.cpp",))
    assert native_gps_build_required(("tools/build_native_gps.sh",))
    assert not native_gps_build_required(("scripts/gps_route_layer.gd",))

    assert city_light_real_data_required(("tools/build_city_light_density.py",))
    assert city_light_real_data_required(("scripts/city_light_renderer.gd",))
    assert not city_light_real_data_required(("scripts/main.gd",))

    assert world_showcase_real_data_required(("tools/prepare_world_showcase.py",))
    assert not world_showcase_real_data_required(("harness/world_showcase/world_showcase.tscn",)), (
        "showcase scene wiring is covered by hosted/headless tests and must not rescan Sweden building data locally"
    )
    assert not world_showcase_real_data_required(("scripts/building_stream_layer.gd",))

    assert building_tiles_required(("tools/build_building_tiles.py",))
    assert building_tiles_required(("scripts/building_runtime_composition.gd",))
    assert not building_tiles_required(("scripts/city_light_renderer.gd",))

    assert not route_geometry_check_required(())
    assert not road_lod_rebuild_required(())
    assert not native_gps_build_required(())
    assert not city_light_real_data_required(())
    assert not world_showcase_real_data_required(())
    assert not building_tiles_required(())

    print("PR check scope tests: OK")


if __name__ == "__main__":
    main()
