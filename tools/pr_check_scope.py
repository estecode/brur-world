#!/usr/bin/env python3
"""Classify whether an expensive PR production-data check is relevant to changed files.

Dependencies:
- Standard library only.
- Used by tools/pr_check.sh; owns validation-scope path policy, not runtime/world behavior.
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


def route_geometry_check_required(changed_paths: Iterable[str]) -> bool:
    """Return whether changed files can alter BRG1/BRH1 generation or validation semantics."""
    return any(path.strip() in ROUTE_GEOMETRY_DATASET_OWNERS for path in changed_paths)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("scope", choices=("route-geometry",))
    args = parser.parse_args()
    changed_paths = [line.strip() for line in sys.stdin if line.strip()]

    if args.scope == "route-geometry":
        print("required" if route_geometry_check_required(changed_paths) else "skip")


if __name__ == "__main__":
    main()
