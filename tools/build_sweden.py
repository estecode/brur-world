#!/usr/bin/env python3
"""Build all Sweden world data: roads, routing, background, POIs, search, buildings, traffic signals and city-light density.

Dependencies:
- Uses the owned offline builders for each runtime dataset.
- Routing is published through build_routing_dataset.py so BRG1/BRS2/BRH1 stay source-aligned.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from build_background import build_background
from build_building_tiles import build_building_tiles
from build_city_light_density import build_city_light_density
from build_features import build_buildings, build_pois
from build_roads import build_roads
from build_routing_dataset import build_routing_dataset
from build_search_binary import build_search_binary
from build_search_index import build_search_index
from build_traffic_signals import build_traffic_signals
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
    print("=== BUILD ROUTING DATASET ===")
    build_routing_dataset(args.pbf, args.output)

    print()
    print("=== BUILD TRAFFIC SIGNALS ===")
    build_traffic_signals(args.pbf, args.output)

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
    print("=== BUILD BUILDING TILES ===")
    build_building_tiles(args.output)

    print()
    print("=== BUILD CITY-LIGHT POI DENSITY ===")
    build_city_light_density(args.output)

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
