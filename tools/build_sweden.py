#!/usr/bin/env python3
"""Build all Sweden world data from one reusable OSM source-ingest boundary.

Dependencies:
- Uses osm_source_cache.py to fan one authoritative OSM scan into route-specific caches.
- Uses the owned offline builders for each runtime dataset.
- Routing is published through build_routing_dataset.py so BRG1/BRS2/BRH1 stay source-aligned.
- Builds the derived building mesh LOD pyramid from authoritative buildings.jsonl.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from build_background import build_background
from build_building_mesh_pyramid import build_building_mesh_pyramid
from build_building_tiles import build_building_tiles
from build_city_light_density import build_city_light_density
from build_features import build_buildings, build_pois
from build_roads import build_roads
from build_routing_dataset import build_routing_dataset
from build_search_binary import build_search_binary
from build_search_index import build_search_index
from build_traffic_signals import build_traffic_signals
from osm_source_cache import ALL_ROUTES, CACHE_DIR_NAME, build_source_caches
from world_common import ensure_pbf


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pbf", type=Path, help="Path to an .osm.pbf file")
    parser.add_argument("--output", type=Path, default=Path("world_data"))
    args = parser.parse_args()

    ensure_pbf(args.pbf)

    print("=== PREPARE OSM SOURCE ROUTE CACHES ===")
    sources = build_source_caches(args.pbf, args.output / CACHE_DIR_NAME, ALL_ROUTES)

    print()
    print("=== BUILD ROADS ===")
    build_roads(sources["highways"], args.output)

    print()
    print("=== BUILD ROUTING DATASET ===")
    build_routing_dataset(sources["highways"], args.output)

    print()
    print("=== BUILD TRAFFIC SIGNALS ===")
    build_traffic_signals(sources["traffic_signals"], args.output)

    print()
    print("=== BUILD BACKGROUND ===")
    build_background(sources["areas"], args.output)

    print()
    print("=== BUILD POIS (FAST) ===")
    build_pois(sources["pois"], args.output)

    print()
    print("=== BUILD BUILDINGS / RELATION POIS (HEAVY) ===")
    build_buildings(sources["areas"], args.output)

    print()
    print("=== BUILD BUILDING TILES ===")
    build_building_tiles(args.output)

    print()
    print("=== BUILD BUILDING MESH LOD PYRAMID ===")
    build_building_mesh_pyramid(args.output)

    print()
    print("=== BUILD CITY-LIGHT POI DENSITY ===")
    build_city_light_density(args.output)

    print()
    print("=== BUILD GPS SEARCH INDEX ===")
    search_jsonl = build_search_index(sources["addresses"], args.output)

    print()
    print("=== BUILD NATIVE GPS SEARCH INDEX ===")
    build_search_binary(search_jsonl, args.output / "search_index.bsi")

    print()
    print(f"Done: {args.output / 'manifest.json'}")
    print("=== BUILD COMPLETE ===")


if __name__ == "__main__":
    main()
