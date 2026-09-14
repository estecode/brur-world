#!/usr/bin/env python3
"""Repeatable real-Sweden acceptance benchmark for issue #220."""

from __future__ import annotations

import argparse
import json
import shutil
import time
from datetime import datetime, timezone
from pathlib import Path

import osmium

from osm_source_cache import ALL_ROUTES, build_source_caches
from source_identity import compute_source_identity

EXPECTED_SOURCE_SHA256 = "5c9682d34aeac727487c06f1bbe22b5976de5c3ada5723c0e446bda3bb316cd2"
EXPECTED_SOURCE_SIZE = 814_508_417
BASELINE_FINALIZE_SECONDS = 5329.7
MAX_COLD_SECONDS = BASELINE_FINALIZE_SECONDS / 2.0
MAX_WARM_SECONDS = 30.0
EXPECTED_HIGHWAY_NODES = 25_418_811
EXPECTED_HIGHWAY_WAYS = 2_290_999
MIN_BUILDING_RECORDS = 3_800_000


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
    class Counter(osmium.SimpleHandler):
        def __init__(self):
            super().__init__(); self.nodes = 0; self.highway_ways = 0; self.scanned_ways = 0; self.started = time.monotonic()
        def node(self, node):
            self.nodes += 1
            if self.nodes % 5_000_000 == 0:
                _log(f"PARITY highways nodes={self.nodes:,} elapsed={time.monotonic() - self.started:.1f}s")
        def way(self, way):
            self.scanned_ways += 1
            if way.tags.get("highway"):
                self.highway_ways += 1
    handler = Counter(); handler.apply_file(str(path))
    return handler.nodes, handler.highway_ways


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pbf", type=Path)
    parser.add_argument("--cache-dir", type=Path, default=Path("/tmp/brur-220-osm-source-cache"))
    parser.add_argument("--report", type=Path, default=Path("/tmp/brur-220-benchmark.json"))
    args = parser.parse_args()

    source = args.pbf.resolve(); cache_dir = args.cache_dir.resolve(); report_path = args.report.resolve()
    if not source.is_file():
        raise SystemExit(f"source missing: {source}")
    if source.stat().st_size != EXPECTED_SOURCE_SIZE:
        raise SystemExit(f"wrong Sweden source size: expected={EXPECTED_SOURCE_SIZE} actual={source.stat().st_size}")

    _log(f"VERIFY source={source}")
    verify_started = time.monotonic(); identity = compute_source_identity(source); verify_seconds = time.monotonic() - verify_started
    if identity.get("digest") != EXPECTED_SOURCE_SHA256:
        raise SystemExit(f"wrong Sweden source SHA256: {identity.get('digest')}")

    if cache_dir.exists():
        _log(f"REMOVE cold-cache={cache_dir}"); shutil.rmtree(cache_dir)
    cache_dir.mkdir(parents=True, exist_ok=False)

    _log(f"COLD START blocks={','.join(ALL_ROUTES)}")
    cold_started = time.monotonic(); build_source_caches(source, cache_dir, ALL_ROUTES); cold_seconds = time.monotonic() - cold_started
    _log(f"COLD DONE elapsed={cold_seconds:.3f}s")
    manifest = _load_json(cache_dir / "manifest.json")
    cold_run = _load_json(cache_dir / "last_run.json")

    _log("PARITY START highways")
    highway_nodes, highway_ways = _count_highway_cache(cache_dir / "highways.osm.pbf")
    _log(f"PARITY DONE highways nodes={highway_nodes:,} ways={highway_ways:,}")
    building_records = int(manifest.get("routes", {}).get("buildings", {}).get("records", -1))

    _log("WARM START")
    warm_started = time.monotonic(); build_source_caches(source, cache_dir, ALL_ROUTES); warm_seconds = time.monotonic() - warm_started
    _log(f"WARM DONE elapsed={warm_seconds:.3f}s")
    warm_run = _load_json(cache_dir / "last_run.json")
    warm_blocks = warm_run.get("blocks", {}) if isinstance(warm_run.get("blocks"), dict) else {}
    all_warm_hits = all(isinstance(warm_blocks.get(route), dict) and warm_blocks[route].get("status") == "CACHE HIT" for route in ALL_ROUTES)

    checks = {
        "source_sha256": identity.get("digest") == EXPECTED_SOURCE_SHA256,
        "source_size": int(identity.get("size_bytes", -1)) == EXPECTED_SOURCE_SIZE,
        "highways_nodes": highway_nodes == EXPECTED_HIGHWAY_NODES,
        "highways_ways": highway_ways == EXPECTED_HIGHWAY_WAYS,
        "building_record_sanity": building_records >= MIN_BUILDING_RECORDS,
        "cold_under_half_finalize_baseline": cold_seconds <= MAX_COLD_SECONDS,
        "warm_under_30_seconds": warm_seconds <= MAX_WARM_SECONDS,
        "warm_all_blocks_cache_hit": all_warm_hits,
    }
    report = {
        "issue": 220,
        "source": str(source),
        "source_identity": identity,
        "source_identity_verify_seconds": verify_seconds,
        "baseline_finalize_only_seconds": BASELINE_FINALIZE_SECONDS,
        "max_cold_seconds": MAX_COLD_SECONDS,
        "max_warm_seconds": MAX_WARM_SECONDS,
        "cold_seconds": cold_seconds,
        "warm_seconds": warm_seconds,
        "cold_speedup_vs_finalize_only": BASELINE_FINALIZE_SECONDS / max(cold_seconds, 1e-9),
        "highways": {"nodes": highway_nodes, "ways": highway_ways},
        "building_records": building_records,
        "cache_dir": str(cache_dir),
        "cache_bytes": sum(path.stat().st_size for path in cache_dir.rglob("*") if path.is_file()),
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
        failed = ", ".join(name for name, passed in checks.items() if not passed)
        raise SystemExit(f"#220 benchmark failed: {failed}")
    _log("PASS")


if __name__ == "__main__":
    main()
