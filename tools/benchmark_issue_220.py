#!/usr/bin/env python3
"""Real-Sweden acceptance benchmark for issue #220's BRUR GeoPackage source path."""
from __future__ import annotations

import argparse
import json
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

from area_source_cache import iter_area_facts
from highway_facts import iter_highway_ways
from normalized_source_facts import iter_facts
from osm_gpkg_source_cache import ALL_ROUTES, build_osm_gpkg_source_caches
from source_identity import compute_source_identity
from windows_build.prepare_runtime_data import selected_runtime_files
from windows_build.runtime_pack import prepare_cached_runtime_pack

MAX_WARM_SECONDS = 30.0
MINIMUM_COLD_BASELINE_SECONDS = 5329.7
MIN_BUILDINGS = 3_800_000
MIN_RUNTIME_REDUCTION = 0.30
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


def _cold_source_seconds(blocks: dict) -> float:
    total = 0.0
    for route in ALL_ROUTES:
        block = blocks.get(route)
        if not isinstance(block, dict) or block.get("status") != "DONE":
            raise ValueError(f"missing cold source-cache timing for {route}")
        total += float(block.get("elapsed_seconds", 0.0))
    return total


def _runtime_footprint(world_dir: Path) -> tuple[int, dict[str, int]]:
    selected = selected_runtime_files(world_dir)
    by_dataset: dict[str, int] = {}
    total = 0
    for relative in selected:
        size = (world_dir / relative).stat().st_size
        total += size
        dataset = relative.parts[0]
        by_dataset[dataset] = by_dataset.get(dataset, 0) + size
    return total, dict(sorted(by_dataset.items()))


def _shipped_runtime_footprint(world_dir: Path) -> tuple[int, dict]:
    """Measure the actual derived Windows runtime pack, including BMC2->BMC3."""
    with tempfile.TemporaryDirectory(prefix="brur-220-runtime-pack-") as temp:
        cache_dir = Path(temp) / "cache"
        report = prepare_cached_runtime_pack(world_dir, cache_dir)
        pack_path = Path(str(report["pack_path"]))
        if not pack_path.is_file() or pack_path.stat().st_size <= 0:
            raise ValueError("production runtime pack was not published")
        return pack_path.stat().st_size, report


def _footprint_payload(world_dir: Path, baseline_runtime_bytes: int | None = None) -> dict:
    runtime_bytes, runtime_by_dataset = _runtime_footprint(world_dir)
    shipped_bytes, shipped_report = _shipped_runtime_footprint(world_dir)
    payload = {
        "world_dir": str(world_dir),
        "production_runtime_bytes": runtime_bytes,
        "production_runtime_gib": round(runtime_bytes / 1024**3, 3),
        "production_runtime_bytes_by_dataset": runtime_by_dataset,
        "shipped_runtime_pack_bytes": shipped_bytes,
        "shipped_runtime_pack_gib": round(shipped_bytes / 1024**3, 3),
        "shipped_runtime_pack": shipped_report,
    }
    if baseline_runtime_bytes is not None:
        reduction = 1.0 - runtime_bytes / baseline_runtime_bytes
        payload.update({
            "baseline_production_runtime_bytes": baseline_runtime_bytes,
            "production_runtime_reduction_fraction": reduction,
            "production_runtime_reduction_percent": round(reduction * 100.0, 3),
            "production_runtime_reduction_30pct": reduction >= MIN_RUNTIME_REDUCTION,
        })
    return payload


def _print_footprint(world_dir: Path, baseline_runtime_bytes: int | None = None) -> None:
    print(json.dumps(_footprint_payload(world_dir, baseline_runtime_bytes), indent=2, sort_keys=True), flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("gpkg", type=Path, nargs="?")
    parser.add_argument("--source-pbf", type=Path)
    parser.add_argument("--world-dir", type=Path, default=Path("/tmp/brur-220-world-data"))
    parser.add_argument("--report", type=Path, default=Path("/tmp/brur-220-benchmark.json"))
    parser.add_argument("--footprint-only", action="store_true", help="Measure an existing completed world build without rebuilding it")
    parser.add_argument("--baseline-runtime-bytes", type=int, help="Measured current-main BMC2 production-runtime baseline for the same Sweden source")
    args = parser.parse_args()

    world_dir = args.world_dir.resolve()
    if args.footprint_only:
        if not world_dir.is_dir(): raise SystemExit(f"world data missing: {world_dir}")
        _print_footprint(world_dir, args.baseline_runtime_bytes)
        return
    if args.gpkg is None: raise SystemExit("gpkg is required unless --footprint-only is used")
    if args.source_pbf is None: raise SystemExit("--source-pbf is required unless --footprint-only is used")

    gpkg = args.gpkg.resolve(); pbf = args.source_pbf.resolve(); report_path = args.report.resolve()
    if not gpkg.is_file(): raise SystemExit(f"GeoPackage missing: {gpkg}")
    if not pbf.is_file(): raise SystemExit(f"source PBF missing: {pbf}")

    _log(f"VERIFY gpkg={gpkg}"); gpkg_identity = compute_source_identity(gpkg)
    _log(f"VERIFY source-pbf={pbf}"); pbf_identity = compute_source_identity(pbf)
    source_counts = {
        "roads": _sql_count(gpkg, "SELECT COUNT(*) FROM lines WHERE highway IS NOT NULL AND TRIM(highway) <> ''"),
        "buildings": _sql_count(gpkg, "SELECT COUNT(*) FROM multipolygons WHERE (building IS NOT NULL AND TRIM(building) <> '') OR other_tags LIKE '%\"building\"=>\"%' OR other_tags LIKE '%\"building:part\"=>\"%'"),
        "traffic_signals": _sql_count(gpkg, "SELECT COUNT(*) FROM points WHERE highway='traffic_signals' OR other_tags LIKE '%\"highway\"=>\"traffic_signals\"%'")
    }
    _log(f"SOURCE roads={source_counts['roads']:,} buildings={source_counts['buildings']:,} signals={source_counts['traffic_signals']:,}")

    if world_dir.exists(): _log(f"REMOVE clean-world={world_dir}"); shutil.rmtree(world_dir)
    _log("FULL BUILD START target=all")
    full_started = time.monotonic()
    subprocess.run([sys.executable, str(TOOLS_DIR/"build_sweden.py"), str(gpkg), "--source-pbf", str(pbf), "--output", str(world_dir), "--target", "all"], check=True)
    full_seconds = time.monotonic() - full_started; _log(f"FULL BUILD DONE elapsed={full_seconds:.3f}s")

    cache_dir = world_dir / "osm_source_cache"
    highway_records = _count_highways(cache_dir / "highways.brfacts")
    building_records = _count_buildings(cache_dir / "areas.baf")
    signal_records = sum(1 for _ in iter_facts(cache_dir / "traffic_signals.brfacts", 1))
    address_records = sum(1 for _ in iter_facts(cache_dir / "addresses.brfacts", 1))
    cold_run = _load_json(cache_dir / "last_run.json")
    cold_blocks = cold_run.get("blocks", {}) if isinstance(cold_run.get("blocks"), dict) else {}
    cold_source_seconds = _cold_source_seconds(cold_blocks)

    _log("WARM SOURCE CACHE START"); warm_started = time.monotonic()
    build_osm_gpkg_source_caches(gpkg, pbf, cache_dir, ALL_ROUTES)
    warm_seconds = time.monotonic()-warm_started; _log(f"WARM SOURCE CACHE DONE elapsed={warm_seconds:.3f}s")
    warm_run = _load_json(cache_dir / "last_run.json"); warm_blocks = warm_run.get("blocks", {}) if isinstance(warm_run.get("blocks"), dict) else {}
    all_warm_hits = all(isinstance(warm_blocks.get(route), dict) and warm_blocks[route].get("status") == "CACHE HIT" for route in ALL_ROUTES)

    manifest = _load_json(cache_dir / "manifest.json"); source_identity = manifest.get("source", {}) if isinstance(manifest.get("source"), dict) else {}
    source_hashes = source_identity.get("sources", {}) if isinstance(source_identity.get("sources"), dict) else {}
    both_hashes_recorded = (
        isinstance(source_hashes.get("brur_gpkg"), dict) and source_hashes["brur_gpkg"].get("digest") == gpkg_identity["digest"] and
        isinstance(source_hashes.get("osm_pbf"), dict) and source_hashes["osm_pbf"].get("digest") == pbf_identity["digest"]
    )

    footprint = _footprint_payload(world_dir, args.baseline_runtime_bytes)
    runtime_bytes = int(footprint["production_runtime_bytes"])
    shipped_runtime_bytes = int(footprint["shipped_runtime_pack_bytes"])
    roads_present = all((world_dir/f"lod{lod}").is_dir() and any((world_dir/f"lod{lod}").glob("*.brtile")) for lod in range(3))

    checks = {
        "source_buildings_sane": source_counts["buildings"] >= MIN_BUILDINGS,
        "highway_records_match_source": highway_records == source_counts["roads"],
        "building_records_match_source": building_records == source_counts["buildings"],
        "traffic_signals_match_source": signal_records == source_counts["traffic_signals"],
        "addresses_present": address_records > 0,
        "gpkg_and_pbf_hashes_recorded": both_hashes_recorded,
        "no_provider_stage_cache": not (cache_dir / "source_stage").exists(),
        "cold_source_cache_at_least_2x_faster_than_minimum_baseline": cold_source_seconds <= MINIMUM_COLD_BASELINE_SECONDS / 2.0,
        "warm_under_30_seconds": warm_seconds <= MAX_WARM_SECONDS,
        "warm_all_blocks_cache_hit": all_warm_hits,
        "production_runtime_selection_valid": runtime_bytes > 0,
        "shipped_runtime_pack_valid": shipped_runtime_bytes > 0,
        "road_tiles_present": roads_present,
    }
    if args.baseline_runtime_bytes is not None:
        checks["production_runtime_reduction_30pct"] = bool(footprint["production_runtime_reduction_30pct"])
    report = {
        "issue":220, "gpkg":str(gpkg), "source_pbf":str(pbf), "gpkg_identity":gpkg_identity, "pbf_identity":pbf_identity,
        "source_counts":source_counts, "normalized_counts":{"highway_records":highway_records,"building_records":building_records,"traffic_signals":signal_records,"addresses":address_records},
        "cold_source_cache_seconds":cold_source_seconds, "minimum_cold_baseline_seconds":MINIMUM_COLD_BASELINE_SECONDS,
        "full_build_seconds":full_seconds, "warm_seconds":warm_seconds, "world_dir":str(world_dir),
        "world_bytes":sum(path.stat().st_size for path in world_dir.rglob("*") if path.is_file()),
        "source_cache_bytes":sum(path.stat().st_size for path in cache_dir.rglob("*") if path.is_file()),
        **{key:value for key,value in footprint.items() if key != "world_dir"},
        "cold_blocks":cold_blocks, "warm_blocks":warm_blocks, "checks":checks, "passed":all(checks.values()), "completed_at":_now(),
    }
    report_path.parent.mkdir(parents=True,exist_ok=True); report_path.write_text(json.dumps(report,indent=2,sort_keys=True),encoding="utf-8")
    print(json.dumps(report,indent=2,sort_keys=True),flush=True); _log(f"REPORT path={report_path}")
    if not report["passed"]: raise SystemExit(f"#220 benchmark failed: {', '.join(name for name,passed in checks.items() if not passed)}")
    _log("PASS")


if __name__ == "__main__": main()
