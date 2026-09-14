#!/usr/bin/env python3
"""Compose selectively rebuildable Sweden world-data targets from source caches."""
from __future__ import annotations

import argparse
import json
import time
from datetime import datetime, timezone
from pathlib import Path

from build_background_sources import build_background_sources
from build_building_mesh_pyramid import build_building_mesh_pyramid
from build_city_light_density import build_city_light_density
from build_features import build_buildings, build_pois
from build_roads import build_roads
from build_routing_dataset import build_routing_dataset
from build_search_binary import build_search_binary
from build_search_index import build_search_index
from build_traffic_signals_sources import build_traffic_signals_sources
from osm_source_cache import CACHE_DIR_NAME, build_source_caches
from world_build_plan import make_plan, parse_targets, record_target, required_source_routes, target_output_bytes
from world_common import ensure_pbf

SEPARATOR = "=" * 72
TOOLS_DIR = Path(__file__).resolve().parent
BUILD_REPORT = "last_build.json"


def _now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def _log(message: str) -> None:
    print(f"[{_now()}] [sweden-build] {message}", flush=True)


def _section(title: str, source: Path | None = None) -> None:
    print(); print(SEPARATOR); _log(title)
    if source is not None: _log(f"source={source}")
    print(SEPARATOR)


def _load_json(path: Path) -> dict:
    if not path.is_file(): return {}
    try: value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError): return {}
    return value if isinstance(value, dict) else {}


def _write_report(path: Path, report: dict) -> None:
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    temp.replace(path)


def _print_plan(plan) -> None:
    _log("PLAN")
    for item in plan: _log(f"PLAN target={item.target} status={item.status} reason={item.reason}")


def _run_target(target: str, sources: dict[str, Path], output: Path) -> None:
    if target == "roads":
        build_roads(sources["highways"], output)
    elif target == "routing":
        build_routing_dataset(sources["highways"], output)
    elif target == "traffic":
        build_traffic_signals_sources(sources["traffic_signals"], sources["highways"], output)
    elif target == "background":
        build_background_sources(sources["areas"], output)
    elif target == "pois":
        build_pois(sources["pois"], output, sources["areas"])
        build_city_light_density(output)
    elif target == "buildings":
        build_buildings(sources["areas"], output)
        build_building_mesh_pyramid(output)
    elif target == "search":
        search_jsonl = build_search_index(sources["addresses"], output)
        build_search_binary(search_jsonl, output / "search_index.bsi")
    else:
        raise ValueError(f"unsupported target: {target}")


def _is_geopackage(path: Path) -> bool:
    return path.suffix.lower() == ".gpkg"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Path to BRUR Sweden .gpkg (preferred) or legacy .osm.pbf")
    parser.add_argument("--source-pbf", type=Path, help="Authoritative OSM PBF from which the BRUR GeoPackage was generated; used for source identity only")
    parser.add_argument("--address-pbf", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--output", type=Path, default=Path("world_data"))
    parser.add_argument("--target", default="all", help="comma-separated: roads,routing,traffic,background,pois,buildings,search or all")
    parser.add_argument("--plan", action="store_true", help="print the resolved build plan and exit")
    args = parser.parse_args()
    if not args.source.is_file(): parser.error(f"source not found: {args.source}")
    if not _is_geopackage(args.source): ensure_pbf(args.source)
    source_pbf = args.source_pbf or args.address_pbf
    if _is_geopackage(args.source):
        if source_pbf is None: parser.error("BRUR GeoPackage builds require --source-pbf for the authoritative PBF identity")
        ensure_pbf(source_pbf)
    args.output.mkdir(parents=True, exist_ok=True)

    try: targets = parse_targets(args.target)
    except ValueError as exc: parser.error(str(exc))
    routes = required_source_routes(targets)
    cache_dir = args.output / CACHE_DIR_NAME
    report_path = args.output / BUILD_REPORT
    total_started = time.monotonic()
    report: dict[str, object] = {
        "started_at": _now(), "source": str(args.source), "source_pbf": str(source_pbf) if source_pbf else None,
        "source_adapter": "gdal-osm-gpkg-direct" if _is_geopackage(args.source) else "legacy-osm-pbf",
        "targets": list(targets), "source_blocks": list(routes), "status": "RUNNING", "target_results": {},
    }
    _write_report(report_path, report)
    try:
        _section("PREPARE REQUIRED SOURCE FACTS", args.source)
        if args.plan:
            source_manifest = _load_json(cache_dir / "manifest.json")
            route_entries = source_manifest.get("routes", {}) if isinstance(source_manifest.get("routes"), dict) else {}
            sources = {route: cache_dir / str(route_entries.get(route, {}).get("file", "missing")) for route in routes}
        else:
            if _is_geopackage(args.source):
                from osm_gpkg_source_cache import build_osm_gpkg_source_caches
                assert source_pbf is not None
                sources = build_osm_gpkg_source_caches(args.source, source_pbf, cache_dir, routes)
            else:
                sources = build_source_caches(args.source, cache_dir, routes)
            source_manifest = _load_json(cache_dir / "manifest.json")
        plan = make_plan(TOOLS_DIR, args.output, source_manifest, targets, cache_dir)
        _print_plan(plan)
        report["plan"] = [{"target": i.target, "status": i.status, "reason": i.reason, "fingerprint": i.fingerprint} for i in plan]
        report["source_cache_run"] = _load_json(cache_dir / "last_run.json")
        _write_report(report_path, report)
        if args.plan:
            report.update({"status": "PLAN", "completed_at": _now()}); _write_report(report_path, report); return
        summaries: list[tuple[str, str, float, int]] = []
        target_results = report["target_results"]; assert isinstance(target_results, dict)
        for item in plan:
            if item.target not in targets or item.status == "SKIP": continue
            if item.status == "BLOCKED" or item.fingerprint is None:
                raise RuntimeError(f"[{item.target}] BLOCKED: {item.reason}")
            if item.status == "CACHE HIT":
                size = target_output_bytes(args.output, item.target)
                summaries.append((item.target, "HIT", 0.0, size)); target_results[item.target] = {"status": "CACHE HIT", "bytes": size}
                _log(f"TARGET target={item.target} status=CACHE-HIT bytes={size:,}"); _write_report(report_path, report); continue
            _log(f"TARGET-START target={item.target} reason={item.reason}")
            started = time.monotonic()
            try: _run_target(item.target, sources, args.output)
            except Exception as exc:
                target_results[item.target] = {"status": "ERROR", "elapsed_seconds": round(time.monotonic()-started,3), "error": f"{type(exc).__name__}: {exc}"}
                _write_report(report_path, report); _log(f"TARGET-ERROR target={item.target} error={type(exc).__name__}: {exc}"); raise
            elapsed = time.monotonic() - started
            record_target(args.output, item.target, item.fingerprint, elapsed)
            size = target_output_bytes(args.output, item.target)
            summaries.append((item.target, "REBUILT", elapsed, size))
            target_results[item.target] = {"status": "REBUILT", "elapsed_seconds": round(elapsed,3), "bytes": size, "fingerprint": item.fingerprint}
            _write_report(report_path, report); _log(f"TARGET-DONE target={item.target} elapsed={elapsed:.1f}s bytes={size:,}")
        for target, status, elapsed, size in summaries: _log(f"SUMMARY target={target} status={status} elapsed={elapsed:.1f}s bytes={size:,}")
        report.update({"status": "DONE", "completed_at": _now(), "elapsed_seconds": round(time.monotonic()-total_started,3)})
        _write_report(report_path, report); _log(f"DONE elapsed={time.monotonic()-total_started:.1f}s report={report_path}")
    except Exception as exc:
        report.update({"status": "ERROR", "completed_at": _now(), "elapsed_seconds": round(time.monotonic()-total_started,3), "error": f"{type(exc).__name__}: {exc}"})
        _write_report(report_path, report); _log(f"ERROR error={type(exc).__name__}: {exc} report={report_path}"); raise


if __name__ == "__main__": main()
