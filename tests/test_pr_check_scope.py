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
    "scripts/building_lod_policy.gd",
    "scripts/building_mesh_chunk_codec.gd",
    "scripts/building_stream_layer.gd",
    "scripts/map_controls_ui.gd",
    "tests/godot/test_map_controls.gd",
    "tools/build_building_mesh_pyramid.py",
    "tools/build_sweden.py",
)


def main() -> None:
    assert not route_geometry_check_required(BUILDING_UI_PR_FILES)
    assert not road_lod_rebuild_required(BUILDING_UI_PR_FILES), (
        "building/UI pipeline changes must not rebuild Sweden road LODs"
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
        "production building changes must prepare or reuse derived building runtime data"
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
        "tools/world_common.py",
        "scripts/road_lod_policy.gd",
    ):
        assert road_lod_rebuild_required((path,)), f"road owner must trigger rebuild: {path}"
    assert not road_lod_rebuild_required(("tools/build_sweden.py",)), (
        "top-level build orchestration changes use targeted stage tests instead of rebuilding all road data"
    )

    assert native_gps_build_required(("native/gps_core.cpp",))
    assert native_gps_build_required(("tools/build_native_gps.sh",))
    assert not native_gps_build_required(("scripts/gps_route_layer.gd",)), (
        "Godot GPS presentation does not require recompiling unchanged native binaries"
    )

    assert city_light_real_data_required(("tools/build_city_light_density.py",))
    assert city_light_real_data_required(("scripts/city_light_renderer.gd",))
    assert not city_light_real_data_required(("scripts/main.gd",))

    assert world_showcase_real_data_required(("tools/prepare_world_showcase.py",))
    assert not world_showcase_real_data_required(("harness/world_showcase/world_showcase.gd",)), (
        "showcase scene/runtime wiring is covered headlessly and does not require regenerating its cache"
    )
    assert not world_showcase_real_data_required(("harness/world_showcase/world_showcase.tscn",))
    assert not world_showcase_real_data_required(("scripts/building_stream_layer.gd",))

    for path in (
        "tools/build_building_tiles.py",
        "tools/build_building_mesh_pyramid.py",
        "tools/build_sweden.py",
        "scripts/building_lod_policy.gd",
        "scripts/building_mesh_chunk_codec.gd",
        "scripts/building_stream_layer.gd",
        "scripts/building_runtime_composition.gd",
        "scenes/main.tscn",
    ):
        assert building_tiles_required((path,)), f"building runtime owner must trigger preparation: {path}"
    assert not building_tiles_required(("scripts/map_controls_ui.gd",)), (
        "pure HUS UI changes do not need building data preparation"
    )
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
