#!/usr/bin/env python3
"""Build independently reusable normalized OSM source-fact caches.

Cold builds use two source-adapter units only:
- one pyosmium/libosmium pass fans out simple facts (highways, POIs, addresses,
  traffic signals) directly into BRUR framed caches;
- one libosmium area pass assembles multipolygons/relations once into the shared
  area cache consumed by buildings/background/relation POIs.

No derived `.osm.pbf` files are written.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

from area_source_cache import FOOTER as AREA_FOOTER, area_source_cache_metadata, build_area_source_cache
from fast_osm_facts import FAST_ROUTES, SCHEMAS, build_fast_facts
from highway_facts import FOOTER as HIGHWAY_FOOTER, validate_highways
from normalized_source_facts import FOOTER as FACT_FOOTER, validate as validate_facts
from source_identity import compute_source_identity
from world_common import ensure_pbf

CACHE_FORMAT = "BOSC4-BRUR-FACTS"
CACHE_DIR_NAME = "osm_source_cache"
EXTRACTOR_VERSION = 2
ROUTE_VERSIONS = {
    "highways": 5,
    "pois": 4,
    "addresses": 4,
    "traffic_signals": 4,
    "areas": 2,
}
ALL_ROUTES = tuple(ROUTE_VERSIONS)
AREA_ROUTE = "areas"


def _now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def _log(message: str) -> None:
    print(f"[{_now()}] [osm-source] {message}", flush=True)


def _load_json(path: Path) -> dict:
    if not path.is_file():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def _atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + f".tmp-{os.getpid()}")
    temp.write_text(json.dumps(value, indent=2, sort_keys=True), encoding="utf-8")
    temp.replace(path)


def _route_filename(route: str) -> str:
    return "areas.baf" if route == AREA_ROUTE else f"{route}.brfacts"


def _artifact_metadata(path: Path) -> dict[str, int]:
    stat = path.stat()
    return {
        "device": int(getattr(stat, "st_dev", 0)),
        "inode": int(getattr(stat, "st_ino", 0)),
        "size_bytes": int(stat.st_size),
        "mtime_ns": int(stat.st_mtime_ns),
        "ctime_ns": int(getattr(stat, "st_ctime_ns", 0)),
    }


def _content_sha256(path: Path, footer_size: int) -> str:
    remaining = path.stat().st_size - footer_size
    if remaining <= 0:
        raise ValueError(f"truncated cache artifact: {path}")
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while remaining:
            chunk = handle.read(min(4 * 1024 * 1024, remaining))
            if not chunk:
                raise ValueError(f"truncated cache artifact while verifying: {path}")
            digest.update(chunk)
            remaining -= len(chunk)
    return digest.hexdigest()


def _source_matches(manifest: dict, source_identity: dict[str, object]) -> bool:
    return isinstance(manifest.get("source"), dict) and manifest["source"] == source_identity


def _route_metadata(path: Path, route: str) -> tuple[dict[str, int | str], int]:
    if route == AREA_ROUTE:
        return area_source_cache_metadata(path), AREA_FOOTER.size
    if route == "highways":
        return validate_highways(path), HIGHWAY_FOOTER.size
    return validate_facts(path, SCHEMAS[route]), FACT_FOOTER.size


def _validate_route_entry(cache_dir: Path, route: str, entry: object) -> tuple[bool, dict | None]:
    if not isinstance(entry, dict):
        return False, None
    if entry.get("version") != ROUTE_VERSIONS[route] or entry.get("extractor_version") != EXTRACTOR_VERSION:
        return False, None
    if entry.get("complete") is not True or entry.get("file") != _route_filename(route):
        return False, None
    path = cache_dir / _route_filename(route)
    if not path.is_file() or entry.get("size_bytes") != path.stat().st_size:
        return False, None
    try:
        meta, footer_size = _route_metadata(path, route)
    except (OSError, ValueError, TypeError, KeyError):
        return False, None
    checksum = str(meta.get("sha256", ""))
    if checksum != entry.get("sha256") or len(checksum) != 64:
        return False, None

    metadata = _artifact_metadata(path)
    if entry.get("artifact_metadata") != metadata:
        _log(f"VERIFY route={route} reason=artifact-metadata-changed bytes={path.stat().st_size:,}")
        try:
            if _content_sha256(path, footer_size) != checksum:
                return False, None
        except (OSError, ValueError):
            return False, None

    refreshed = dict(entry)
    refreshed["artifact_metadata"] = metadata
    return True, refreshed


def _entry(route: str, report: dict, path: Path, elapsed_s: float, build_unit: str) -> dict:
    checksum = str(report.get("sha256", ""))
    if len(checksum) != 64:
        raise RuntimeError(f"missing normalized-cache checksum for {route}")
    return {
        "version": ROUTE_VERSIONS[route],
        "extractor_version": EXTRACTOR_VERSION,
        "extractor": "pyosmium/libosmium",
        "build_unit": build_unit,
        "complete": True,
        "file": _route_filename(route),
        "records": int(report.get("records", 0)),
        "size_bytes": int(path.stat().st_size),
        "sha256": checksum,
        "artifact_metadata": _artifact_metadata(path),
        "elapsed_seconds": round(elapsed_s, 3),
    }


def build_source_caches(source: Path, cache_dir: Path, routes: Iterable[str] = ALL_ROUTES) -> dict[str, Path]:
    ensure_pbf(source)
    requested = tuple(dict.fromkeys(routes))
    unknown = [route for route in requested if route not in ROUTE_VERSIONS]
    if unknown:
        raise ValueError(f"Unknown OSM source cache route(s): {', '.join(unknown)}")
    cache_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = cache_dir / "manifest.json"
    report_path = cache_dir / "last_run.json"
    run: dict[str, object] = {
        "format": CACHE_FORMAT,
        "status": "RUNNING",
        "started_at": _now(),
        "requested": list(requested),
        "blocks": {},
    }
    _atomic_json(report_path, run)

    identity_started = time.monotonic()
    source_identity = compute_source_identity(source, cache_dir / "source_identity.json")
    identity_elapsed = time.monotonic() - identity_started
    old_manifest = _load_json(manifest_path)
    same_source = _source_matches(old_manifest, source_identity)
    old_routes = old_manifest.get("routes", {}) if same_source and isinstance(old_manifest.get("routes"), dict) else {}
    entries: dict[str, dict] = {}
    stale: set[str] = set()

    if same_source:
        for route in ALL_ROUTES:
            valid, refreshed = _validate_route_entry(cache_dir, route, old_routes.get(route))
            if valid and refreshed is not None:
                entries[route] = refreshed
    for route in requested:
        if route not in entries:
            stale.add(route)

    outputs = {route: cache_dir / _route_filename(route) for route in requested}
    blocks = run["blocks"]
    assert isinstance(blocks, dict)
    _log(
        f"PLAN routes={','.join(requested)} source-sha256={str(source_identity['digest'])[:12]}... "
        f"identity={identity_elapsed:.3f}s"
    )
    for route in requested:
        status = "REBUILD" if route in stale else "CACHE HIT"
        block: dict[str, object] = {"status": status}
        if route not in stale:
            block["sha256"] = entries[route]["sha256"]
            block["bytes"] = entries[route]["size_bytes"]
        blocks[route] = block
        _log(f"PLAN route={route} status={status}")
    _atomic_json(report_path, run)

    try:
        stale_fast = tuple(route for route in FAST_ROUTES if route in stale)
        if stale_fast:
            _log(f"START unit=fast-facts routes={','.join(stale_fast)}")
            started = time.monotonic()
            reports = build_fast_facts(source, {route: cache_dir / _route_filename(route) for route in stale_fast})
            elapsed = time.monotonic() - started
            for route in stale_fast:
                path = cache_dir / _route_filename(route)
                entries[route] = _entry(route, reports[route], path, elapsed, "fast-facts")
                blocks[route] = {"status": "DONE", **entries[route]}
            _atomic_json(manifest_path, {"format": CACHE_FORMAT, "source": source_identity, "routes": entries})
            _atomic_json(report_path, run)
            _log(f"DONE unit=fast-facts elapsed={elapsed:.1f}s")

        if AREA_ROUTE in stale:
            _log("START unit=areas route=areas")
            started = time.monotonic()
            path = cache_dir / _route_filename(AREA_ROUTE)
            report = build_area_source_cache(source, path)
            elapsed = time.monotonic() - started
            entries[AREA_ROUTE] = _entry(AREA_ROUTE, report, path, elapsed, "areas")
            blocks[AREA_ROUTE] = {"status": "DONE", **entries[AREA_ROUTE]}
            _atomic_json(manifest_path, {"format": CACHE_FORMAT, "source": source_identity, "routes": entries})
            _atomic_json(report_path, run)
            _log(f"DONE unit=areas elapsed={elapsed:.1f}s")

        _atomic_json(manifest_path, {"format": CACHE_FORMAT, "source": source_identity, "routes": entries})
        run.update({"status": "DONE", "completed_at": _now(), "source": source_identity})
        _atomic_json(report_path, run)
        if not stale:
            _log(f"CACHE HIT routes={','.join(requested)}")
        else:
            _log(f"DONE routes={','.join(requested)}")
        return outputs
    except BaseException as exc:
        run.update({"status": "ERROR", "completed_at": _now(), "source": source_identity, "error": f"{type(exc).__name__}: {exc}"})
        _atomic_json(report_path, run)
        _log(f"ERROR {type(exc).__name__}: {exc}")
        raise


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("pbf", type=Path)
    parser.add_argument("--cache-dir", type=Path, default=Path("world_data") / CACHE_DIR_NAME)
    parser.add_argument("--routes", default=",".join(ALL_ROUTES))
    args = parser.parse_args()
    routes = tuple(route.strip() for route in args.routes.split(",") if route.strip())
    outputs = build_source_caches(args.pbf, args.cache_dir, routes)
    for route, path in outputs.items():
        print(f"{route}: {path}")


if __name__ == "__main__":
    main()
