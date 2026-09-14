#!/usr/bin/env python3
"""Compose selectively rebuildable Sweden world-data targets.

Dataset builders keep their own semantics. This file only resolves source-cache
dependencies, prints a plan, executes stale requested targets, and records the
fingerprints used for directed invalidation.
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

from build_background import build_background
from build_building_mesh_pyramid import build_building_mesh_pyramid
from build_city_light_density import build_city_light_density
from build_features import build_buildings, build_pois
from build_roads import build_roads
from build_routing_dataset import build_routing_dataset
from build_search_binary import build_search_binary
from build_search_index import build_search_index
from build_traffic_signals import build_traffic_signals
from osm_source_cache import CACHE_DIR_NAME, build_source_caches
from world_build_plan import (
    make_plan,
    parse_targets,
    record_target,
    required_source_routes,
    target_output_bytes,
)
from world_common import ensure_pbf

SEPARATOR = "=" * 72
TOOLS_DIR = Path(__file__).resolve().parent


def _section(title: str, source: Path | None = None) -> None:
    print()
    print(SEPARATOR)
    print(f"=== {title} ===")
    if source is not None:
        print(f"source: {source}")
    print(SEPARATOR)


def _load_json(path: Path) -> dict:
    if not path.is_file():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def _print_plan(plan) -> None:
    print("[plan] Sweden build")
    for item in plan:
        print(f"[plan] {item.target:<12} {item.status:<9} reason={item.reason}")


def _run_target(target: str, sources: dict[str, Path], output: Path) -> None:
    if target == "roads":
        build_roads(sources["highways"], output)
    elif target == "routing":
        build_routing_dataset(sources["highways"], output)
    elif target == "traffic":
        build_traffic_signals(sources["traffic_signals"], output)
    elif target == "background":
        build_background(sources["areas"], output)
    elif target == "pois":
        build_pois(sources["pois"], output, sources["areas"])
        build_city_light_density(output)
    elif target == "buildings":
        build_buildings(sources["areas"], output)
        # BMC2 is the canonical production building representation. Legacy
        # building_tiles are intentionally not rebuilt or shipped here.
        build_building_mesh_pyramid(output)
    elif target == "search":
        search_jsonl = build_search_index(sources["addresses"], output)
        build_search_binary(search_jsonl, output / "search_index.bsi")
    else:
        raise ValueError(f"unsupported target: {target}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pbf", type=Path, help="Path to an .osm.pbf file")
    parser.add_argument("--output", type=Path, default=Path("world_data"))
    parser.add_argument(
        "--target", default="all",
        help="comma-separated: roads,routing,traffic,background,pois,buildings,search or all",
    )
    parser.add_argument("--plan", action="store_true", help="print the resolved build plan and exit")
    args = parser.parse_args()
    ensure_pbf(args.pbf)
    args.output.mkdir(parents=True, exist_ok=True)

    try:
        targets = parse_targets(args.target)
    except ValueError as exc:
        parser.error(str(exc))
    routes = required_source_routes(targets)
    cache_dir = args.output / CACHE_DIR_NAME

    total_started = time.monotonic()
    _section("PREPARE REQUIRED OSM SOURCE CACHES", args.pbf)
    if args.plan:
        # Planning never performs an expensive source traversal. Existing source
        # artifacts are inspected fail-closed; missing/incompatible dependencies
        # surface as BLOCKED in the target plan.
        source_manifest = _load_json(cache_dir / "manifest.json")
        sources = {route: cache_dir / ("areas.baf" if route == "areas" else f"{route}.osm") for route in routes}
    else:
        sources = build_source_caches(args.pbf, cache_dir, routes)
        source_manifest = _load_json(cache_dir / "manifest.json")

    plan = make_plan(TOOLS_DIR, args.output, source_manifest, targets, cache_dir)
    _print_plan(plan)
    if args.plan:
        return

    summaries: list[tuple[str, str, float, int]] = []
    for item in plan:
        if item.target not in targets or item.status == "SKIP":
            continue
        if item.status == "BLOCKED" or item.fingerprint is None:
            raise SystemExit(f"[{item.target}] BLOCKED: {item.reason}")
        if item.status == "CACHE HIT":
            summaries.append((item.target, "HIT", 0.0, target_output_bytes(args.output, item.target)))
            continue
        print(f"[{item.target}] START reason={item.reason}", flush=True)
        started = time.monotonic()
        try:
            _run_target(item.target, sources, args.output)
        except Exception as exc:
            print(f"[{item.target}] ERROR {type(exc).__name__}: {exc}", flush=True)
            raise
        elapsed = time.monotonic() - started
        record_target(args.output, item.target, item.fingerprint, elapsed)
        size = target_output_bytes(args.output, item.target)
        summaries.append((item.target, "REBUILT", elapsed, size))
        print(f"[{item.target}] DONE elapsed={elapsed:.1f}s runtime-bytes={size:,}", flush=True)

    print()
    for target, status, elapsed, size in summaries:
        print(f"[summary] {target:<12} {status:<7} {elapsed:>8.1f}s {size:>14,} bytes")
    print(f"[summary] total                 {time.monotonic() - total_started:>8.1f}s")
    print(f"[summary] manifest={args.output / 'manifest.json'}")


if __name__ == "__main__":
    main()
