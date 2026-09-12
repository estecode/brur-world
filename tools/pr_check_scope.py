#!/usr/bin/env python3
"""Classify whether expensive PR-check preparation is relevant to changed files.

Dependencies:
- Standard library only.
- Used by tools/pr_check.sh and PR-owned local checks.
- Owns validation-scope path policy, not runtime/world behavior.
"""

from __future__ import annotations

import argparse
import sys
from collections.abc import Iterable


ROUTE_GEOMETRY_DATASET_OWNERS = frozenset(
    {
        "tools/build_routing.py",
        "tools/build_routing_dataset.py",
        "tools/check_route_geometry_dataset.py",
        "tools/route_geometry.py",
        "tools/world_common.py",
    }
)

ROAD_LOD_DATASET_OWNERS = frozenset(
    {
        "tools/build_roads.py",
        "tools/world_common.py",
        "scripts/road_lod_policy.gd",
    }
)

CITY_LIGHT_OWNERS = frozenset(
    {
        "tools/build_city_light_density.py",
        "tools/test_city_lights_real_data.sh",
        "scripts/city_light_model.gd",
        "scripts/city_light_renderer.gd",
        "tests/godot/test_city_lights.gd",
        "tests/godot/test_city_lights_real_data.gd",
    }
)

WORLD_SHOWCASE_OWNERS = frozenset(
    {
        "tools/prepare_world_showcase.py",
        "tests/test_world_showcase_prepare.py",
    }
)

BUILDING_TILE_OWNERS = frozenset(
    {
        "tools/build_building_tiles.py",
        "tools/build_sweden.py",
        "scripts/building_stream_layer.gd",
        "scripts/building_runtime_composition.gd",
        "scenes/main.tscn",
    }
)

NATIVE_GPS_EXACT_OWNERS = frozenset(
    {
        "tools/build_native_gps.sh",
        "requirements.txt",
    }
)


def _paths(changed_paths: Iterable[str]) -> tuple[str, ...]:
    return tuple(path.strip() for path in changed_paths if path.strip())


def route_geometry_check_required(changed_paths: Iterable[str]) -> bool:
    """Return whether changed files can alter BRG1/BRH1 generation or validation semantics."""
    return any(path in ROUTE_GEOMETRY_DATASET_OWNERS for path in _paths(changed_paths))


def road_lod_rebuild_required(changed_paths: Iterable[str]) -> bool:
    """Return whether the PR can alter generated road LOD data or its policy contract."""
    return any(path in ROAD_LOD_DATASET_OWNERS for path in _paths(changed_paths))


def native_gps_build_required(changed_paths: Iterable[str]) -> bool:
    """Return whether exact-PR native GPS binaries must be rebuilt from source."""
    for path in _paths(changed_paths):
        if path.startswith("native/") or path in NATIVE_GPS_EXACT_OWNERS:
            return True
    return False


def city_light_real_data_required(changed_paths: Iterable[str]) -> bool:
    """Return whether local city-light derived-data validation is relevant."""
    return any(path in CITY_LIGHT_OWNERS for path in _paths(changed_paths))


def world_showcase_real_data_required(changed_paths: Iterable[str]) -> bool:
    """Return whether the expensive showcase cache itself must be regenerated locally."""
    return any(path in WORLD_SHOWCASE_OWNERS for path in _paths(changed_paths))


def building_tiles_required(changed_paths: Iterable[str]) -> bool:
    """Return whether production building-tile real-data preparation is relevant."""
    return any(path in BUILDING_TILE_OWNERS for path in _paths(changed_paths))


SCOPES = {
    "route-geometry": route_geometry_check_required,
    "road-lod": road_lod_rebuild_required,
    "native-gps": native_gps_build_required,
    "city-lights": city_light_real_data_required,
    "world-showcase": world_showcase_real_data_required,
    "building-tiles": building_tiles_required,
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("scope", choices=tuple(SCOPES))
    args = parser.parse_args()
    changed_paths = [line.strip() for line in sys.stdin if line.strip()]
    print("required" if SCOPES[args.scope](changed_paths) else "skip")


if __name__ == "__main__":
    main()
