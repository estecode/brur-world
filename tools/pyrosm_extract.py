#!/usr/bin/env python3
"""Extract one semantic OSM source-cache block with pyrosm.

This is deliberately a source-adapter only. It preserves source OSM topology in
small, independently rebuildable PBF caches; downstream BRUR builders continue
to own world semantics and runtime artifacts.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import resource
import time
from datetime import datetime, timezone
from pathlib import Path

MIN_PYROSM_VERSION = (0, 13, 1)

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
    print(f"[{_now()}] [pyrosm-extract] {message}", flush=True)


def _version_tuple(value: str) -> tuple[int, ...]:
    parts: list[int] = []
    for part in value.split("."):
        digits = "".join(ch for ch in part if ch.isdigit())
        if not digits:
            break
        parts.append(int(digits))
    return tuple(parts)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _peak_rss_bytes() -> int:
    value = int(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
    return value if platform.system() == "Darwin" else value * 1024


def _background_area_filters() -> list[str]:
    filters = [f'["natural"="{value}"]' for value in BACKGROUND_NATURAL]
    filters.extend(f'["landuse"="{value}"]' for value in BACKGROUND_LANDUSE)
    filters.extend(['["waterway"="riverbank"]', '["water"]'])
    return filters


def _criteria(domain: str):
    if domain == "buildings":
        return ['["building"]', '["building:part"]']
    if domain == "pois":
        filters = [f'["{key}"]' for key in POI_KEYS]
        filters.extend([
            '["highway"~"^(speed_camera|services|rest_area|bus_stop|elevator)$"]',
            '["enforcement"]',
            '["surveillance"]',
        ])
        filters.extend(f'["{key}"]' for key in CAMERA_KEYS)
        return filters
    if domain == "addresses":
        return [
            '["addr:housenumber"]["addr:street"]',
            '["addr:housenumber"]["addr:place"]',
        ]
    if domain == "traffic_signals":
        return '["highway"="traffic_signals"]'
    if domain == "background_areas":
        return _background_area_filters()
    if domain == "coastlines":
        return '["natural"="coastline"]'
    if domain == "admin_boundaries":
        return '["boundary"="administrative"]["admin_level"="2"]'
    if domain == "background":
        return _background_area_filters() + [
            '["natural"="coastline"]',
            '["boundary"="administrative"]["admin_level"="2"]',
        ]
    raise ValueError(f"unsupported pyrosm domain: {domain}")


def _extract(osm, domain: str):
    if domain == "highways":
        return osm.get_network(
            network_type="all",
            custom_filter='["highway"]',
            filter_type="keep",
        )
    return osm.get_data_by_custom_criteria(custom_filter=_criteria(domain), filter_type="keep")


def _counts(frame) -> dict[str, int]:
    result = {"records": int(len(frame))}
    if "osm_type" in frame.columns:
        for key, value in frame["osm_type"].value_counts().to_dict().items():
            result[str(key)] = int(value)
    if hasattr(frame, "geometry"):
        for key, value in frame.geometry.geom_type.value_counts().to_dict().items():
            result[f"geometry:{key}"] = int(value)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--domain", required=True, choices=(
        "highways", "buildings", "pois", "addresses", "traffic_signals",
        "background_areas", "coastlines", "admin_boundaries", "background",
    ))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--workers", default="auto")
    args = parser.parse_args()

    try:
        import pyrosm
        from pyrosm import OSM
    except ImportError as exc:
        raise SystemExit(
            "pyrosm >= 0.13.1 is required. Install with `micromamba install -n brur-pyrosm -c conda-forge pyrosm` "
            "or install the project requirements into the active Python environment."
        ) from exc

    version = str(getattr(pyrosm, "__version__", "0"))
    if _version_tuple(version) < MIN_PYROSM_VERSION:
        raise SystemExit(f"pyrosm >= 0.13.1 required, found {version}")
    if not args.source.is_file() or not args.source.name.endswith(".osm.pbf"):
        raise SystemExit(f"source must be an existing .osm.pbf: {args.source}")
    workers = int(args.workers) if str(args.workers).isdigit() else args.workers

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    temp = args.output.parent / f".{args.output.stem}.tmp-{os.getpid()}-{time.time_ns()}.osm.pbf"
    started = time.monotonic()
    _log(f"START domain={args.domain} source={args.source.name} workers={workers} pyrosm={version}")

    try:
        try:
            cleared = OSM.clear_cache(args.source)
        except Exception:
            cleared = 0
        if cleared:
            _log(f"CLEARED internal-pyrosm-cache files={cleared}")

        osm = OSM(args.source, engine="out_of_core", workers=workers, keep_metadata=False)
        frame = _extract(osm, args.domain)
        if frame is None:
            raise RuntimeError(f"pyrosm returned no frame for domain {args.domain}")
        counts = _counts(frame)
        extract_elapsed = time.monotonic() - started
        _log(f"EXTRACTED domain={args.domain} records={counts['records']:,} elapsed={extract_elapsed:.1f}s")

        write_started = time.monotonic()
        osm.write_pbf(frame, temp, subset_only=True)
        write_elapsed = time.monotonic() - write_started
        if not temp.is_file() or temp.stat().st_size <= 0:
            raise RuntimeError(f"pyrosm did not publish a valid PBF for {args.domain}")

        checksum_started = time.monotonic()
        checksum = _sha256(temp)
        checksum_elapsed = time.monotonic() - checksum_started
        temp.replace(args.output)
        total_elapsed = time.monotonic() - started
        report = {
            "domain": args.domain,
            "source": str(args.source),
            "output": str(args.output),
            "pyrosm_version": version,
            "engine": "out_of_core",
            "workers": workers,
            "counts": counts,
            "records": counts["records"],
            "size_bytes": args.output.stat().st_size,
            "sha256": checksum,
            "extract_seconds": round(extract_elapsed, 3),
            "write_seconds": round(write_elapsed, 3),
            "checksum_seconds": round(checksum_elapsed, 3),
            "elapsed_seconds": round(total_elapsed, 3),
            "peak_rss_bytes": _peak_rss_bytes(),
            "completed_at": _now(),
        }
        args.report.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
        _log(
            f"DONE domain={args.domain} records={counts['records']:,} bytes={report['size_bytes']:,} "
            f"sha256={checksum[:12]}... elapsed={total_elapsed:.1f}s peak-rss={report['peak_rss_bytes']:,}"
        )
    except Exception:
        try:
            temp.unlink()
        except OSError:
            pass
        raise


if __name__ == "__main__":
    main()
