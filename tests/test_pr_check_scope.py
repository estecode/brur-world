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

from pr_check_scope import route_geometry_check_required  # noqa: E402


CITY_LIGHT_PR_FILES = (
    ".github/workflows/pr-validation.yml",
    "scenes/main.tscn",
    "scripts/city_light_model.gd",
    "scripts/city_light_renderer.gd",
    "scripts/day_night_environment_adapter.gd",
    "scripts/main.gd",
    "scripts/sun_runtime_controller.gd",
    "tests/godot/test_city_lights.gd",
    "tests/godot/test_city_lights_real_data.gd",
    "tools/build_city_light_density.py",
    "tools/build_sweden.py",
    "tools/pr_check.sh",
    "tools/test_city_lights.sh",
    "tools/test_city_lights_real_data.sh",
)


def main() -> None:
    assert not route_geometry_check_required(CITY_LIGHT_PR_FILES), (
        "city-light PR changes must not trigger the full route-geometry dataset scan"
    )

    for path in (
        "tools/build_routing.py",
        "tools/build_routing_dataset.py",
        "tools/check_route_geometry_dataset.py",
        "tools/route_geometry.py",
        "tools/world_common.py",
    ):
        assert route_geometry_check_required((path,)), f"routing owner must trigger scan: {path}"

    assert not route_geometry_check_required(("native/gps_route_geometry.h",)), (
        "native route rendering/runtime changes do not alter the BRG1/BRH1 production dataset"
    )
    assert not route_geometry_check_required(("scripts/gps_route_layer.gd",)), (
        "GPS presentation changes do not alter the BRG1/BRH1 production dataset"
    )
    assert not route_geometry_check_required(()), "empty PR diff must skip the expensive scan"

    print("PR check scope tests: OK")


if __name__ == "__main__":
    main()
