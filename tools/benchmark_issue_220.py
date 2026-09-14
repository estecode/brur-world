#!/usr/bin/env python3
"""Repeatable real-Sweden acceptance benchmark for issue #220.

Measures the actual clean `build_sweden.py --target all` wall clock, then checks
source-fact parity and warm-cache reuse. The acceptance target is a complete
world-data build in <=15 minutes on the reference Mac.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from area_source_cache import iter_area_facts
from highway_facts import iter_highway_ways
from osm_source_cache import ALL_ROUTES, build_source_caches
from source_identity import compute_source_identity

EXPECTED_SOURCE_SHA256 = "5c9682d34aeac727487c06f1bbe22b5976de5c3ada5723c0e446bda3bb316cd2"
EXPECTED_SOURCE_SIZE = 814_508_417
BASELINE_FINALIZE_SECONDS = 5329.7
MAX_SOURCE_CACHE_SECONDS = BASELINE_FINALIZE_SECONDS / 2.0
MAX_WARM_SECONDS = 30.0
MAX_FULL_BUILD_SECONDS = 15.0 * 60.0
EXPECTED_HIGHWAY_NODES = 25_418_811
EXPECTED_HIGHWAY_WAYS = 2_290_999
MIN_BUILDING_RECORDS = 3_800_000
TOOLS_DIR = Path(__file__).resolve().parent


def _now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def _log(message: str) -> None:
    print(f"[{_now()}] [220-benchmark] {message}", flush=True)


def _load_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected object: {path}")
    return value


def _count_highway_cache(path: Path) -> tuple[int, int]:
    node_ids: set[int] = set()
    ways = 0
    started = time.monotonic()
    for ways, way in enumerate(iter_highway_ways(path), 1):
        node_ids.update(int(value) for value in way.node_ids)
        if ways % 250_000 == 0:
            _log(f"PARITY highways ways={ways:,} unique-nodes={len(node_ids):,} elapsed={time.monotonic()-started:.1f}s")
    return len(node_ids), ways


def _count_buildings(path: Path) -> int:
    buildings = 0
    started = time.monotonic()
    for scanned, fact in enumerate(iter_area_facts(path), 1):
        tags = fact.get("tags", {})
        if tags.get("building") is not None or tags.get("building:part") is not None:
            buildings += 1
        if scanned % 250_000 == 0:
            _log(f"PARITY areas={scanned:,} buildings={buildings:,} elapsed={time.monotonic()-started:.1f}s")
    return buildings


def _source_cache_seconds(cold_run: dict) -> float:
    blocks = cold_run.get("blocks", {}) if isinstance(cold_run.get("blocks"), dict) else {}
    by_unit: dict[str, float] = {}
    for value in blocks.values():
        if not isinstance(value, dict):
            continue
        unit = str(value.get("build_unit") or "")
        elapsed = value.get("elapsed_seconds")
        if unit and isinstance(elapsed, (int, float)):
            by_unit[unit] = max(by_unit.get(unit, 0.0), float(elapsed))
    return sum(by_unit.values())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pbf", type=Path)
    parser.add_argument("--world-dir", type=Path, default=Path("/tmp/brur-220-world-data"))
    parser.add_argument("--report", type=Path, default=Path("/tmp/brur-220-benchmark.json"))
    args = parser.parse_args()

    source = args.pbf.resolve()
    world_dir = args.world_dir.resolve()
    report_path = args.report.resolve()
    if not source.is_file():
        raise SystemExit(f"source missing: {source}")
    if source.stat().st_size != EXPECTED_SOURCE_SIZE:
        raise SystemExit(f"wrong Sweden source size: expected={EXPECTED_SOURCE_SIZE} actual={source.stat().st_size}")

    _log(f"VERIFY source={source}")
    verify_started = time.monotonic()
    identity = compute_source_identity(source)
    verify_seconds = time.monotonic() - verify_started
    if identity.get("digest") != EXPECTED_SOURCE_SHA256:
        raise SystemExit(f"wrong Sweden source SHA256: {identity.get('digest')}")

    if world_dir.exists():
        _log(f"REMOVE clean-world={world_dir}")
        shutil.rmtree(world_dir)

    _log("FULL BUILD START target=all")
    full_started = time.monotonic()
    subprocess.run(
        [sys.executable, str(TOOLS_DIR / "build_sweden.py"), str(source), "--output", str(world_dir), "--target", "all"],
        check=True,
    )
    full_seconds = time.monotonic() - full_started
    _log(f"FULL BUILD DONE elapsed={full_seconds:.3f}s")

    cache_dir = world_dir / "osm_source_cache"
    cold_run = _load_json(cache_dir / "last_run.json")
    source_cache_seconds = _source_cache_seconds(cold_run)

    _log("PARITY START highways")
    highway_nodes, highway_ways = _count_highway_cache(cache_dir / "highways.brfacts")
    _log(f"PARITY DONE highways nodes={highway_nodes:,} ways={highway_ways:,}")

    _log("PARITY START buildings")
    building_records = _count_buildings(cache_dir / "areas.baf")
    _log(f"PARITY DONE buildings={building_records:,}")

    _log("WARM SOURCE CACHE START")
    warm_started = time.monotonic()
    build_source_caches(source, cache_dir, ALL_ROUTES)
    warm_seconds = time.monotonic() - warm_started
    _log(f"WARM SOURCE CACHE DONE elapsed={warm_seconds:.3f}s")
    warm_run = _load_json(cache_dir / "last_run.json")
    warm_blocks = warm_run.get("blocks", {}) if isinstance(warm_run.get("blocks"), dict) else {}
    all_warm_hits = all(
        isinstance(warm_blocks.get(route), dict) and warm_blocks[route].get("status") == "CACHE HIT"
        for route in ALL_ROUTES
    )

    required_runtime = (
        "background.brmap",
        "routing.brg",
        "routing_geometry.brh",
        "routing_snap.brs",
        "traffic_signals.json",
        "search_index.bsi",
        "buildings.jsonl",
    )
    runtime_present = all((world_dir / name).is_file() and (world_dir / name).stat().st_size > 0 for name in required_runtime)
    roads_present = all((world_dir / f"lod{lod}").is_dir() and any((world_dir / f"lod{lod}").glob("*.brtile")) for lod in range(3))

    checks = {
        "source_sha256": identity.get("digest") == EXPECTED_SOURCE_SHA256,
        "source_size": int(identity.get("size_bytes", -1)) == EXPECTED_SOURCE_SIZE,
        "highways_nodes": highway_nodes == EXPECTED_HIGHWAY_NODES,
        "highways_ways": highway_ways == EXPECTED_HIGHWAY_WAYS,
        "building_record_sanity": building_records >= MIN_BUILDING_RECORDS,
        "source_cache_under_half_finalize_baseline": source_cache_seconds <= MAX_SOURCE_CACHE_SECONDS,
        "full_world_build_under_15_minutes": full_seconds <= MAX_FULL_BUILD_SECONDS,
        "warm_under_30_seconds": warm_seconds <= MAX_WARM_SECONDS,
        "warm_all_blocks_cache_hit": all_warm_hits,
        "runtime_outputs_present": runtime_present,
        "road_tiles_present": roads_present,
    }
    report = {
        "issue": 220,
        "source": str(source),
        "source_identity": identity,
        "source_identity_verify_seconds": verify_seconds,
        "baseline_finalize_only_seconds": BASELINE_FINALIZE_SECONDS,
        "max_source_cache_seconds": MAX_SOURCE_CACHE_SECONDS,
        "max_full_build_seconds": MAX_FULL_BUILD_SECONDS,
        "max_warm_seconds": MAX_WARM_SECONDS,
        "source_cache_seconds": source_cache_seconds,
        "full_build_seconds": full_seconds,
        "warm_seconds": warm_seconds,
        "highways": {"nodes": highway_nodes, "ways": highway_ways},
        "building_records": building_records,
        "world_dir": str(world_dir),
        "world_bytes": sum(path.stat().st_size for path in world_dir.rglob("*") if path.is_file()),
        "source_cache_bytes": sum(path.stat().st_size for path in cache_dir.rglob("*") if path.is_file()),
        "cold_blocks": cold_run.get("blocks", {}),
        "warm_blocks": warm_blocks,
        "checks": checks,
        "passed": all(checks.values()),
        "completed_at": _now(),
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True), flush=True)
    _log(f"REPORT path={report_path}")
    if not report["passed"]:
        raise SystemExit(f"#220 benchmark failed: {', '.join(name for name, passed in checks.items() if not passed)}")
    _log("PASS")


if __name__ == "__main__":
    main()
