#!/usr/bin/env python3
"""Build all Sweden world data: roads, background, buildings and POIs."""

from __future__ import annotations

import argparse
from pathlib import Path

from build_background import build_background
from build_features import build_features
from build_roads import build_roads
from world_common import ensure_pbf


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pbf", type=Path, help="Path to an .osm.pbf file")
    parser.add_argument("--output", type=Path, default=Path("world_data"))
    args = parser.parse_args()

    ensure_pbf(args.pbf)

    print("=== BUILD ROADS ===")
    build_roads(args.pbf, args.output)

    print()
    print("=== BUILD BACKGROUND ===")
    build_background(args.pbf, args.output)

    print()
    print("=== BUILD FEATURES ===")
    build_features(args.pbf, args.output)

    print()
    print(f"Done: {args.output / 'manifest.json'}")
    print("=== BUILD COMPLETE ===")


if __name__ == "__main__":
    main()
