#!/usr/bin/env python3
"""Build all Sweden world data from one reusable OSM source-ingest boundary.

Dependencies:
- Uses osm_source_cache.py to fan one authoritative OSM scan into route-specific caches.
- Uses the owned offline builders for each runtime dataset.
- Routing is published through build_routing_dataset.py so BRG1/BRS2/BRH1 stay source-aligned.
"""

from __future__ import annotations

import argparse
import json
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
from osm_source_cache import ALL_ROUTES, CACHE_DIR_NAME, build_source_caches
from world_common import ensure_pbf

SEPARATOR = "=" * 72


def _section(title: str, source: Path | None = None) -> None:
    print()
    print(SEPARATOR)
    print(f"=== {title} ===")
    if source is not None:
        print(f"source: {source}")
    print(SEPARATOR)


def _print_cache_summary(source: Path, cache_dir: Path, sources: dict[str, Path]) -> None:
    manifest = json.loads((cache_dir / "manifest.json").read_text(encoding="utf-8"))
    source_identity = manifest.get("source", {})
    digest = source_identity.get("digest", "unknown")

    _section("SWEDEN OSM SOURCE")
    print(f"file:   {source}")
    print(f"sha256: {digest}")
    print(f"cache:  {cache_dir}")
    print("routes:")
    for route in ALL_ROUTES:
        print(f"  {route:<16} -> {sources[route]}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pbf", type=Path, help="Path to an .osm.pbf file")
    parser.add_argument("--output", type=Path, default=Path("world_data"))
    args = parser.parse_args()

    ensure_pbf(args.pbf)

    _section("PREPARE OSM SOURCE ROUTE CACHES", args.pbf)
    cache_dir = args.output / CACHE_DIR_NAME
    sources = build_source_caches(args.pbf, cache_dir, ALL_ROUTES)
    _print_cache_summary(args.pbf, cache_dir, sources)

    _section("BUILD ROADS", sources["highways"])
    build_roads(sources["highways"], args.output)

    _section("BUILD ROUTING DATASET", sources["highways"])
    build_routing_dataset(sources["highways"], args.output)

    _section("BUILD TRAFFIC SIGNALS", sources["traffic_signals"])
    build_traffic_signals(sources["traffic_signals"], args.output)

    _section("BUILD BACKGROUND", sources["areas"])
    build_background(sources["areas"], args.output)

    _section("BUILD POIS (FAST)", sources["pois"])
    build_pois(sources["pois"], args.output)

    _section("BUILD BUILDINGS / RELATION POIS (HEAVY)", sources["areas"])
    build_buildings(sources["areas"], args.output)

    _section("BUILD BUILDING TILES")
    build_building_tiles(args.output)

    _section("BUILD CITY-LIGHT POI DENSITY")
    build_city_light_density(args.output)

    _section("BUILD GPS SEARCH INDEX", sources["addresses"])
    search_jsonl = build_search_index(sources["addresses"], args.output)

    _section("BUILD NATIVE GPS SEARCH INDEX", search_jsonl)
    build_search_binary(search_jsonl, args.output / "search_index.bsi")

    _section("BUILD COMPLETE")
    print(f"manifest: {args.output / 'manifest.json'}")


if __name__ == "__main__":
    main()
