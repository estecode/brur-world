#!/usr/bin/env python3
"""Real-Sweden acceptance benchmark for issue #220's GeoPackage source path."""
from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from area_source_cache import iter_area_facts
from geofabrik_source_cache import ALL_ROUTES, build_geofabrik_source_caches
from highway_facts import iter_highway_ways
from normalized_source_facts import iter_facts
from source_identity import compute_source_identity

MAX_WARM_SECONDS = 30.0
MAX_FULL_BUILD_SECONDS = 15.0 * 60.0
MIN_BUILDINGS = 3_800_000
TOOLS_DIR = Path(__file__).resolve().parent


def _now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def _log(message: str) -> None:
    print(f"[{_now()}] [220-benchmark] {message}", flush=True)


def _load_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict): raise ValueError(f"expected object: {path}")
    return value


def _sql_count(path: Path, sql: str) -> int:
    connection = sqlite3.connect(path)
    try:
        row = connection.execute(sql).fetchone()
        return int(row[0]) if row is not None else 0
    finally:
        connection.close()


def _count_highways(path: Path) -> int:
    count = 0
    for count, _ in enumerate(iter_highway_ways(path), 1):
        if count % 250_000 == 0: _log(f"PARITY highways={count:,}")
    return count


def _count_buildings(path: Path) -> int:
    buildings = 0
    for scanned, fact in enumerate(iter_area_facts(path), 1):
        tags = fact.get("tags", {})
        if tags.get("building") is not None or tags.get("building:part") is not None: buildings += 1
        if scanned % 250_000 == 0: _log(f"PARITY areas={scanned:,} buildings={buildings:,}")
    return buildings


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("gpkg", type=Path)
    parser.add_argument("--address-pbf", type=Path, required=True)
    parser.add_argument("--world-dir", type=Path, default=Path("/tmp/brur-220-world-data"))
    parser.add_argument("--report", type=Path, default=Path("/tmp/brur-220-benchmark.json"))
    args = parser.parse_args()

    gpkg = args.gpkg.resolve(); pbf = args.address_pbf.resolve(); world_dir = args.world_dir.resolve(); report_path = args.report.resolve()
    if not gpkg.is_file(): raise SystemExit(f"GeoPackage missing: {gpkg}")
    if not pbf.is_file(): raise SystemExit(f"address PBF missing: {pbf}")

    _log(f"VERIFY gpkg={gpkg}"); gpkg_identity = compute_source_identity(gpkg)
    _log(f"VERIFY address-pbf={pbf}"); pbf_identity = compute_source_identity(pbf)
    source_counts = {
        "roads": _sql_count(gpkg, "SELECT COUNT(*) FROM gis_osm_roads_free"),
        "buildings": _sql_count(gpkg, "SELECT COUNT(*) FROM gis_osm_buildings_a_free"),
        "traffic_signals": _sql_count(gpkg, "SELECT COUNT(*) FROM gis_osm_traffic_free WHERE fclass='traffic_signals'"),
    }
    _log(f"SOURCE roads={source_counts['roads']:,} buildings={source_counts['buildings']:,} signals={source_counts['traffic_signals']:,}")

    if world_dir.exists(): _log(f"REMOVE clean-world={world_dir}"); shutil.rmtree(world_dir)
    _log("FULL BUILD START target=all")
    full_started = time.monotonic()
    subprocess.run([sys.executable, str(TOOLS_DIR/"build_sweden.py"), str(gpkg), "--address-pbf", str(pbf), "--output", str(world_dir), "--target", "all"], check=True)
    full_seconds = time.monotonic() - full_started; _log(f"FULL BUILD DONE elapsed={full_seconds:.3f}s")

    cache_dir = world_dir / "osm_source_cache"
    highway_records = _count_highways(cache_dir / "highways.brfacts")
    building_records = _count_buildings(cache_dir / "areas.baf")
    signal_records = sum(1 for _ in iter_facts(cache_dir / "traffic_signals.brfacts", 1))
    address_records = sum(1 for _ in iter_facts(cache_dir / "addresses.brfacts", 1))
    cold_run = _load_json(cache_dir / "last_run.json")

    _log("WARM SOURCE CACHE START"); warm_started = time.monotonic()
    build_geofabrik_source_caches(gpkg, pbf, cache_dir, ALL_ROUTES)
    warm_seconds = time.monotonic()-warm_started; _log(f"WARM SOURCE CACHE DONE elapsed={warm_seconds:.3f}s")
    warm_run = _load_json(cache_dir / "last_run.json"); warm_blocks = warm_run.get("blocks", {}) if isinstance(warm_run.get("blocks"), dict) else {}
    all_warm_hits = all(isinstance(warm_blocks.get(route), dict) and warm_blocks[route].get("status") == "CACHE HIT" for route in ALL_ROUTES)

    required_runtime = ("background.brmap", "routing.brg", "routing_geometry.brh", "routing_snap.brs", "traffic_signals.json", "search_index.bsi", "buildings.jsonl")
    runtime_present = all((world_dir/name).is_file() and (world_dir/name).stat().st_size > 0 for name in required_runtime)
    roads_present = all((world_dir/f"lod{lod}").is_dir() and any((world_dir/f"lod{lod}").glob("*.brtile")) for lod in range(3))
    stage_dir = cache_dir / "source_stage"
    stage_present = all((stage_dir/name).is_file() and (stage_dir/name).stat().st_size > 0 for name in ("roads.sqlite","traffic.sqlite","pois.sqlite","areas.sqlite","osm_supplement.osm.pbf"))

    checks = {
        "source_buildings_sane": source_counts["buildings"] >= MIN_BUILDINGS,
        "highway_records_cover_source_rows": highway_records >= source_counts["roads"],
        "building_records_match_source": building_records == source_counts["buildings"],
        "traffic_signals_match_source": signal_records == source_counts["traffic_signals"],
        "addresses_present": address_records > 0,
        "staged_source_files_present": stage_present,
        "full_world_build_under_15_minutes": full_seconds <= MAX_FULL_BUILD_SECONDS,
        "warm_under_30_seconds": warm_seconds <= MAX_WARM_SECONDS,
        "warm_all_blocks_cache_hit": all_warm_hits,
        "runtime_outputs_present": runtime_present,
        "road_tiles_present": roads_present,
    }
    report = {
        "issue":220, "gpkg":str(gpkg), "address_pbf":str(pbf), "gpkg_identity":gpkg_identity, "pbf_identity":pbf_identity,
        "source_counts":source_counts, "normalized_counts":{"highway_records":highway_records,"building_records":building_records,"traffic_signals":signal_records,"addresses":address_records},
        "full_build_seconds":full_seconds, "warm_seconds":warm_seconds, "world_dir":str(world_dir),
        "world_bytes":sum(path.stat().st_size for path in world_dir.rglob("*") if path.is_file()),
        "source_cache_bytes":sum(path.stat().st_size for path in cache_dir.rglob("*") if path.is_file()),
        "stage_bytes":sum(path.stat().st_size for path in stage_dir.rglob("*") if path.is_file()),
        "cold_blocks":cold_run.get("blocks",{}), "warm_blocks":warm_blocks, "checks":checks, "passed":all(checks.values()), "completed_at":_now(),
    }
    report_path.parent.mkdir(parents=True,exist_ok=True); report_path.write_text(json.dumps(report,indent=2,sort_keys=True),encoding="utf-8")
    print(json.dumps(report,indent=2,sort_keys=True),flush=True); _log(f"REPORT path={report_path}")
    if not report["passed"]: raise SystemExit(f"#220 benchmark failed: {', '.join(name for name,passed in checks.items() if not passed)}")
    _log("PASS")


if __name__ == "__main__": main()
