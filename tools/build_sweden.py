#!/usr/bin/env python3
"""Build all Sweden world data: roads, routing, background, POIs, search and buildings."""

from __future__ import annotations

import argparse
from pathlib import Path

from build_background import build_background
from build_features import build_buildings, build_pois
from build_roads import build_roads
from build_routing import build_routing
from build_search_binary import build_search_binary
from build_search_index import build_search_index
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
    print("=== BUILD ROUTING ===")
    build_routing(args.pbf, args.output)

    print()
    print("=== BUILD BACKGROUND ===")
    build_background(args.pbf, args.output)

    print()
    print("=== BUILD POIS (FAST) ===")
    build_pois(args.pbf, args.output)

    print()
    print("=== BUILD BUILDINGS / RELATION POIS (HEAVY) ===")
    build_buildings(args.pbf, args.output)

    print()
    print("=== BUILD GPS SEARCH INDEX ===")
    search_jsonl = build_search_index(args.pbf, args.output)

    print()
    print("=== BUILD NATIVE GPS SEARCH INDEX ===")
    build_search_binary(search_jsonl, args.output / "search_index.bsi")

    print()
    print(f"Done: {args.output / 'manifest.json'}")
    print("=== BUILD COMPLETE ===")


if __name__ == "__main__":
    main()
