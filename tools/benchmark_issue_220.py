#!/usr/bin/env python3
"""Repeatable real-Sweden acceptance benchmark for issue #220.

This intentionally targets the exact source/machine performance gate recorded
on #220. It builds a fresh BOSC2 cache, immediately resolves it warm, validates
routing-source parity for the highways route, and writes an inspectable report.
"""

from __future__ import annotations

import argparse
import json
import shutil
import time
from pathlib import Path

from osm_source_cache import ALL_ROUTES, build_source_caches
from source_identity import compute_source_identity

EXPECTED_SOURCE_SHA256 = "5c9682d34aeac727487c06f1bbe22b5976de5c3ada5723c0e446bda3bb316cd2"
EXPECTED_SOURCE_SIZE = 814_508_417
BASELINE_FINALIZE_SECONDS = 5329.7
MAX_COLD_SECONDS = BASELINE_FINALIZE_SECONDS / 2.0
MAX_WARM_SECONDS = 30.0
EXPECTED_HIGHWAY_NODES = 25_418_811
EXPECTED_HIGHWAY_WAYS = 2_290_999


def _load_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected object: {path}")
    return value


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pbf", type=Path)
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=Path("/tmp/brur-220-osm-source-cache"),
        help="dedicated disposable benchmark cache directory",
    )
    parser.add_argument("--report", type=Path, default=Path("/tmp/brur-220-benchmark.json"))
    args = parser.parse_args()

    source = args.pbf.resolve()
    cache_dir = args.cache_dir.resolve()
    report_path = args.report.resolve()
    if not source.is_file():
        raise SystemExit(f"source missing: {source}")
    if source.stat().st_size != EXPECTED_SOURCE_SIZE:
        raise SystemExit(
            f"wrong Sweden source size: expected={EXPECTED_SOURCE_SIZE} actual={source.stat().st_size}"
        )

    print(f"[220-benchmark] VERIFY source={source}", flush=True)
    verify_started = time.monotonic()
    identity = compute_source_identity(source)
    verify_seconds = time.monotonic() - verify_started
    if identity.get("digest") != EXPECTED_SOURCE_SHA256:
        raise SystemExit(
            f"wrong Sweden source SHA256: expected={EXPECTED_SOURCE_SHA256} actual={identity.get('digest')}"
        )

    if cache_dir.exists():
        print(f"[220-benchmark] REMOVE cold cache={cache_dir}", flush=True)
        shutil.rmtree(cache_dir)
    cache_dir.mkdir(parents=True, exist_ok=False)

    print("[220-benchmark] COLD START", flush=True)
    cold_started = time.monotonic()
    build_source_caches(source, cache_dir, ALL_ROUTES)
    cold_seconds = time.monotonic() - cold_started
    print(f"[220-benchmark] COLD DONE elapsed={cold_seconds:.3f}s", flush=True)

    manifest = _load_json(cache_dir / "manifest.json")
    highway_counts = manifest.get("routes", {}).get("highways", {}).get("counts", {})
    highway_nodes = int(highway_counts.get("nodes", -1))
    highway_ways = int(highway_counts.get("ways", -1))
    if highway_nodes != EXPECTED_HIGHWAY_NODES or highway_ways != EXPECTED_HIGHWAY_WAYS:
        raise SystemExit(
            "highways parity failed: "
            f"expected nodes/ways={EXPECTED_HIGHWAY_NODES}/{EXPECTED_HIGHWAY_WAYS} "
            f"actual={highway_nodes}/{highway_ways}"
        )

    print("[220-benchmark] WARM START", flush=True)
    warm_started = time.monotonic()
    build_source_caches(source, cache_dir, ALL_ROUTES)
    warm_seconds = time.monotonic() - warm_started
    print(f"[220-benchmark] WARM DONE elapsed={warm_seconds:.3f}s", flush=True)

    cold_speedup_vs_finalize_only = BASELINE_FINALIZE_SECONDS / max(cold_seconds, 1e-9)
    checks = {
        "source_sha256": identity.get("digest") == EXPECTED_SOURCE_SHA256,
        "source_size": int(identity.get("size_bytes", -1)) == EXPECTED_SOURCE_SIZE,
        "highways_nodes": highway_nodes == EXPECTED_HIGHWAY_NODES,
        "highways_ways": highway_ways == EXPECTED_HIGHWAY_WAYS,
        "cold_under_half_finalize_baseline": cold_seconds <= MAX_COLD_SECONDS,
        "warm_under_30_seconds": warm_seconds <= MAX_WARM_SECONDS,
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
        "cold_speedup_vs_finalize_only": cold_speedup_vs_finalize_only,
        "highways": {"nodes": highway_nodes, "ways": highway_ways},
        "cache_dir": str(cache_dir),
        "cache_bytes": sum(path.stat().st_size for path in cache_dir.rglob("*") if path.is_file()),
        "checks": checks,
        "passed": all(checks.values()),
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True), flush=True)
    print(f"[220-benchmark] report={report_path}", flush=True)
    if not report["passed"]:
        failed = ", ".join(name for name, passed in checks.items() if not passed)
        raise SystemExit(f"#220 benchmark failed: {failed}")
    print("[220-benchmark] PASS", flush=True)


if __name__ == "__main__":
    main()
