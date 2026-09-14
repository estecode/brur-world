#!/usr/bin/env python3
"""Build independently rebuildable OSM source-cache blocks with pyrosm.

The authoritative Sweden PBF is touched only when a requested block is missing,
stale or incompatible. Downstream BRUR builders always consume these caches.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

from source_identity import compute_source_identity
from world_common import ensure_pbf

CACHE_FORMAT = "BOSC3-PYROSM"
CACHE_DIR_NAME = "osm_source_cache"
EXTRACTOR_VERSION = 1
HEARTBEAT_SECONDS = 10.0
ROUTE_VERSIONS = {
    "highways": 3,
    "buildings": 1,
    "pois": 3,
    "addresses": 3,
    "traffic_signals": 3,
    "background_areas": 1,
    "coastlines": 1,
    "admin_boundaries": 1,
}
ALL_ROUTES = tuple(ROUTE_VERSIONS)
TOOLS_DIR = Path(__file__).resolve().parent
EXTRACTOR = TOOLS_DIR / "pyrosm_extract.py"


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
    return f"{route}.osm.pbf"


def _artifact_metadata(path: Path) -> dict[str, int]:
    stat = path.stat()
    return {
        "device": int(getattr(stat, "st_dev", 0)),
        "inode": int(getattr(stat, "st_ino", 0)),
        "size_bytes": int(stat.st_size),
        "mtime_ns": int(stat.st_mtime_ns),
        "ctime_ns": int(getattr(stat, "st_ctime_ns", 0)),
    }


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _source_matches(manifest: dict, source_identity: dict[str, object]) -> bool:
    source = manifest.get("source")
    return isinstance(source, dict) and source == source_identity


def _validate_route_entry(cache_dir: Path, route: str, entry: object) -> tuple[bool, dict | None]:
    if not isinstance(entry, dict):
        return False, None
    if entry.get("version") != ROUTE_VERSIONS[route] or entry.get("complete") is not True:
        return False, None
    if entry.get("extractor_version") != EXTRACTOR_VERSION:
        return False, None
    if entry.get("file") != _route_filename(route):
        return False, None
    checksum = entry.get("sha256")
    if not isinstance(checksum, str) or len(checksum) != 64:
        return False, None
    path = cache_dir / _route_filename(route)
    if not path.is_file() or path.stat().st_size <= 0:
        return False, None
    expected_size = entry.get("size_bytes")
    if not isinstance(expected_size, int) or expected_size != path.stat().st_size:
        return False, None

    metadata = _artifact_metadata(path)
    if entry.get("artifact_metadata") == metadata:
        return True, dict(entry)

    # Strong artifact metadata changed. Fail closed by verifying the exact file
    # checksum once, then refresh the shortcut metadata for later warm runs.
    _log(f"VERIFY route={route} reason=artifact-metadata-changed bytes={path.stat().st_size:,}")
    if _sha256(path) != checksum:
        return False, None
    refreshed = dict(entry)
    refreshed["artifact_metadata"] = metadata
    return True, refreshed


def _pyrosm_command() -> list[str]:
    override = os.environ.get("BRUR_PYROSM_PYTHON", "").strip()
    if override:
        return [override, str(EXTRACTOR)]
    if importlib.util.find_spec("pyrosm") is not None:
        return [sys.executable, str(EXTRACTOR)]
    micromamba = shutil.which("micromamba")
    if micromamba:
        env_name = os.environ.get("BRUR_PYROSM_ENV", "brur-pyrosm")
        return [micromamba, "run", "-n", env_name, "python", str(EXTRACTOR)]
    raise SystemExit(
        "pyrosm is not available in this Python and micromamba was not found. "
        "Install pyrosm>=0.13.1 or create `brur-pyrosm` with conda-forge."
    )


def _run_extractor(source: Path, cache_dir: Path, route: str) -> dict:
    destination = cache_dir / _route_filename(route)
    report_path = cache_dir / f".extract-{route}-{os.getpid()}-{time.time_ns()}.json"
    command = _pyrosm_command() + [
        str(source), "--domain", route, "--output", str(destination), "--report", str(report_path),
    ]
    _log(f"START route={route} source={source.name} output={destination.name}")
    started = time.monotonic()
    process = subprocess.Popen(command)
    try:
        while True:
            try:
                code = process.wait(timeout=HEARTBEAT_SECONDS)
                break
            except subprocess.TimeoutExpired:
                _log(f"PROGRESS route={route} status=pyrosm-running elapsed={time.monotonic() - started:.1f}s")
        if code != 0:
            raise RuntimeError(f"pyrosm extractor failed for {route} with exit code {code}")
        report = _load_json(report_path)
        if report.get("domain") != route or not destination.is_file():
            raise RuntimeError(f"pyrosm extractor produced incomplete report/output for {route}")
        _log(
            f"DONE route={route} records={int(report.get('records', 0)):,} "
            f"bytes={destination.stat().st_size:,} sha256={str(report.get('sha256', ''))[:12]}... "
            f"elapsed={time.monotonic() - started:.1f}s"
        )
        return report
    finally:
        try:
            report_path.unlink()
        except OSError:
            pass


def _entry_from_report(route: str, report: dict, path: Path) -> dict:
    checksum = report.get("sha256")
    if not isinstance(checksum, str) or len(checksum) != 64:
        raise RuntimeError(f"missing exact cache checksum for {route}")
    return {
        "version": ROUTE_VERSIONS[route],
        "extractor_version": EXTRACTOR_VERSION,
        "extractor": "pyrosm",
        "pyrosm_version": report.get("pyrosm_version"),
        "complete": True,
        "file": _route_filename(route),
        "records": int(report.get("records", 0)),
        "counts": report.get("counts", {}),
        "size_bytes": int(path.stat().st_size),
        "sha256": checksum,
        "artifact_metadata": _artifact_metadata(path),
        "extract_seconds": report.get("extract_seconds"),
        "write_seconds": report.get("write_seconds"),
        "checksum_seconds": report.get("checksum_seconds"),
        "elapsed_seconds": report.get("elapsed_seconds"),
        "peak_rss_bytes": report.get("peak_rss_bytes"),
    }


def build_source_caches(source: Path, cache_dir: Path, routes: Iterable[str] = ALL_ROUTES) -> dict[str, Path]:
    ensure_pbf(source)
    requested = tuple(dict.fromkeys(routes))
    unknown = [route for route in requested if route not in ROUTE_VERSIONS]
    if unknown:
        raise ValueError(f"Unknown OSM source cache route(s): {', '.join(unknown)}")
    cache_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = cache_dir / "manifest.json"
    run_report_path = cache_dir / "last_run.json"

    run_report: dict[str, object] = {
        "format": CACHE_FORMAT,
        "started_at": _now(),
        "requested": list(requested),
        "blocks": {},
        "status": "RUNNING",
    }
    _atomic_json(run_report_path, run_report)

    identity_started = time.monotonic()
    source_identity = compute_source_identity(source, cache_dir / "source_identity.json")
    identity_elapsed = time.monotonic() - identity_started
    manifest = _load_json(manifest_path)
    same_source = _source_matches(manifest, source_identity)
    old_routes = manifest.get("routes", {}) if same_source and isinstance(manifest.get("routes"), dict) else {}
    route_entries: dict[str, dict] = {}
    stale: set[str] = set()

    for route in requested:
        valid, refreshed = _validate_route_entry(cache_dir, route, old_routes.get(route)) if same_source else (False, None)
        if valid and refreshed is not None:
            route_entries[route] = refreshed
        else:
            stale.add(route)
    if same_source:
        for route, entry in old_routes.items():
            if route not in requested and route in ROUTE_VERSIONS and isinstance(entry, dict):
                valid, refreshed = _validate_route_entry(cache_dir, route, entry)
                if valid and refreshed is not None:
                    route_entries[route] = refreshed

    outputs = {route: cache_dir / _route_filename(route) for route in requested}
    _log(
        f"PLAN routes={','.join(requested)} source-sha256={str(source_identity['digest'])[:12]}... "
        f"identity={identity_elapsed:.3f}s"
    )
    blocks = run_report["blocks"]
    assert isinstance(blocks, dict)
    for route in requested:
        if route in stale:
            _log(f"PLAN route={route} status=REBUILD reason=missing/stale/incompatible")
            blocks[route] = {"status": "REBUILD", "started_at": None}
        else:
            checksum = str(route_entries[route].get("sha256", ""))
            _log(f"PLAN route={route} status=CACHE-HIT checksum={checksum[:12]}...")
            blocks[route] = {"status": "CACHE HIT", "sha256": checksum, "bytes": route_entries[route].get("size_bytes")}
    _atomic_json(run_report_path, run_report)

    if not stale:
        run_report.update({"status": "DONE", "completed_at": _now(), "source": source_identity})
        _atomic_json(run_report_path, run_report)
        # Refresh strong artifact metadata if it was verified above.
        _atomic_json(manifest_path, {"format": CACHE_FORMAT, "source": source_identity, "routes": route_entries})
        _log(f"CACHE HIT routes={','.join(requested)}")
        return outputs

    try:
        for route in requested:
            if route not in stale:
                continue
            block = blocks[route]
            assert isinstance(block, dict)
            block["started_at"] = _now()
            _atomic_json(run_report_path, run_report)
            started = time.monotonic()
            try:
                report = _run_extractor(source, cache_dir, route)
                entry = _entry_from_report(route, report, outputs[route])
                route_entries[route] = entry
                block.update({
                    "status": "DONE",
                    "completed_at": _now(),
                    "elapsed_seconds": round(time.monotonic() - started, 3),
                    "records": entry["records"],
                    "bytes": entry["size_bytes"],
                    "sha256": entry["sha256"],
                    "peak_rss_bytes": entry.get("peak_rss_bytes"),
                })
                # Publish each completed block independently so a later failure
                # never discards useful completed work.
                _atomic_json(manifest_path, {
                    "format": CACHE_FORMAT,
                    "source": source_identity,
                    "routes": route_entries,
                })
                _atomic_json(run_report_path, run_report)
            except Exception as exc:
                block.update({"status": "ERROR", "completed_at": _now(), "error": f"{type(exc).__name__}: {exc}"})
                run_report.update({"status": "ERROR", "completed_at": _now(), "source": source_identity})
                _atomic_json(run_report_path, run_report)
                _log(f"ERROR route={route} error={type(exc).__name__}: {exc}")
                raise
    except Exception:
        raise

    run_report.update({"status": "DONE", "completed_at": _now(), "source": source_identity})
    _atomic_json(run_report_path, run_report)
    _log(f"DONE routes={','.join(requested)}")
    return outputs


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
