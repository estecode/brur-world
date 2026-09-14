#!/usr/bin/env python3
"""Extract dumb per-domain OSM staging files with pyrosm, one domain at a time.

This is intentionally only the source-extraction boundary for issue #220:

    Sweden PBF -> pyrosm domain result -> atomic file on disk -> next domain

The orchestrator does not inspect, normalize, project, deduplicate, hash, count or
otherwise interpret pyrosm result contents. BRUR cache conversion happens later,
after every requested extraction file has been published.
"""
from __future__ import annotations

import argparse
import gc
import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

MIN_PYROSM_VERSION = (0, 13, 1)
DOMAINS = ("buildings", "highways", "addresses", "pois", "traffic_signals", "background")

POI_KEYS = (
    "amenity", "shop", "tourism", "leisure", "office", "healthcare", "emergency",
    "public_transport", "railway", "aeroway", "craft", "historic", "sport", "club",
    "man_made", "information", "advertising",
)
CAMERA_KEYS = (
    "camera:direction", "camera:mount", "camera:type", "camera:features",
    "camera:angle", "camera:orientation", "camera:zone",
)
BACKGROUND_LANDUSE = (
    "reservoir", "forest", "farmland", "farmyard", "meadow", "grass", "orchard", "vineyard",
    "residential", "commercial", "industrial", "retail", "basin",
)
BACKGROUND_NATURAL = ("water", "wood", "bay", "strait")


def _now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def _log(message: str) -> None:
    print(f"[{_now()}] [pyrosm-stage] {message}", flush=True)


def _version_tuple(value: str) -> tuple[int, ...]:
    parts: list[int] = []
    for part in value.split("."):
        digits = "".join(ch for ch in part if ch.isdigit())
        if not digits:
            break
        parts.append(int(digits))
    return tuple(parts)


def _criteria(domain: str):
    if domain == "buildings":
        return ['["building"]', '["building:part"]']
    if domain == "addresses":
        return ['["addr:housenumber"]["addr:street"]', '["addr:housenumber"]["addr:place"]']
    if domain == "pois":
        filters = [f'["{key}"]' for key in POI_KEYS]
        filters.extend([
            '["highway"~"^(speed_camera|services|rest_area|bus_stop|elevator)$"]',
            '["enforcement"]',
            '["surveillance"]',
        ])
        filters.extend(f'["{key}"]' for key in CAMERA_KEYS)
        return filters
    if domain == "traffic_signals":
        return '["highway"="traffic_signals"]'
    if domain == "background":
        filters = [f'["natural"="{value}"]' for value in BACKGROUND_NATURAL]
        filters.extend(f'["landuse"="{value}"]' for value in BACKGROUND_LANDUSE)
        filters.extend([
            '["waterway"="riverbank"]',
            '["water"]',
            '["natural"="coastline"]',
            '["boundary"="administrative"]["admin_level"="2"]',
        ])
        return filters
    raise ValueError(f"unsupported pyrosm domain: {domain}")


def _extract(osm, domain: str):
    if domain == "highways":
        return osm.get_network(network_type="all", custom_filter='["highway"]', filter_type="keep")
    return osm.get_data_by_custom_criteria(custom_filter=_criteria(domain), filter_type="keep")


def _make_osm(source: Path, workers: int | str):
    try:
        import pyrosm
        from pyrosm import OSM
    except ImportError as exc:
        raise SystemExit(
            "pyrosm >= 0.13.1 is required. Install with `micromamba install -n brur-pyrosm -c conda-forge pyrosm`."
        ) from exc
    version = str(getattr(pyrosm, "__version__", "0"))
    if _version_tuple(version) < MIN_PYROSM_VERSION:
        raise SystemExit(f"pyrosm >= 0.13.1 required, found {version}")
    try:
        cleared = OSM.clear_cache(source)
    except Exception:
        cleared = 0
    if cleared:
        _log(f"CLEARED internal-pyrosm-cache files={cleared}")
    return OSM(source, engine="out_of_core", workers=workers, keep_metadata=False), version


def extract_source_stage(
    source: Path,
    output_dir: Path,
    domains: Iterable[str] = DOMAINS,
    workers: int | str = "auto",
    *,
    osm_and_version=None,
) -> dict:
    source = Path(source)
    output_dir = Path(output_dir)
    requested = tuple(dict.fromkeys(domains))
    unknown = [domain for domain in requested if domain not in DOMAINS]
    if unknown:
        raise ValueError(f"unsupported pyrosm domain(s): {', '.join(unknown)}")
    if not source.is_file() or not source.name.endswith(".osm.pbf"):
        raise ValueError(f"source must be an existing .osm.pbf: {source}")
    if not requested:
        raise ValueError("at least one extraction domain is required")

    output_dir.mkdir(parents=True, exist_ok=True)
    osm, version = osm_and_version if osm_and_version is not None else _make_osm(source, workers)
    started = time.monotonic()
    report: dict[str, object] = {
        "format": "BRUR-PYROSM-STAGE-1",
        "source": str(source),
        "source_size_bytes": source.stat().st_size,
        "domains": list(requested),
        "pyrosm_version": version,
        "engine": "out_of_core",
        "workers": workers,
        "results": {},
        "started_at": _now(),
    }
    results = report["results"]
    assert isinstance(results, dict)

    for domain in requested:
        destination = output_dir / f"{domain}.osm.pbf"
        temp = output_dir / f".{domain}.tmp-{os.getpid()}-{time.time_ns()}.osm.pbf"
        domain_started = time.monotonic()
        _log(f"START domain={domain}")
        frame = None
        try:
            extract_started = time.monotonic()
            frame = _extract(osm, domain)
            extract_seconds = time.monotonic() - extract_started
            if frame is None:
                raise RuntimeError(f"pyrosm returned no result for {domain}")

            write_started = time.monotonic()
            osm.write_pbf(frame, temp, subset_only=True)
            write_seconds = time.monotonic() - write_started
        finally:
            frame = None
            gc.collect()

        if not temp.is_file() or temp.stat().st_size <= 0:
            try:
                temp.unlink()
            except OSError:
                pass
            raise RuntimeError(f"pyrosm did not publish a valid extraction for {domain}")
        temp.replace(destination)
        elapsed = time.monotonic() - domain_started
        results[domain] = {
            "file": destination.name,
            "size_bytes": destination.stat().st_size,
            "extract_seconds": round(extract_seconds, 3),
            "write_seconds": round(write_seconds, 3),
            "elapsed_seconds": round(elapsed, 3),
        }
        _log(
            f"DONE domain={domain} bytes={destination.stat().st_size:,} "
            f"extract={extract_seconds:.1f}s write={write_seconds:.1f}s elapsed={elapsed:.1f}s"
        )

    report.update({"status": "DONE", "elapsed_seconds": round(time.monotonic() - started, 3), "completed_at": _now()})
    manifest = output_dir / "extract_manifest.json"
    temp_manifest = manifest.with_suffix(".json.tmp")
    temp_manifest.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    temp_manifest.replace(manifest)
    _log(f"DONE all domains={len(requested)} elapsed={report['elapsed_seconds']:.1f}s bytes={sum(int(v['size_bytes']) for v in results.values()):,}")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--domains", default=",".join(DOMAINS))
    parser.add_argument("--workers", default="auto")
    args = parser.parse_args()
    domains = tuple(value.strip() for value in args.domains.split(",") if value.strip())
    workers: int | str = int(args.workers) if str(args.workers).isdigit() else args.workers
    extract_source_stage(args.source, args.output, domains, workers)


if __name__ == "__main__":
    main()
