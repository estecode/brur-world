#!/usr/bin/env python3
"""Stage provider-specific GDAL OSM GeoPackage rows for BRUR source normalization.

This module intentionally stops at the source-adapter boundary. It copies only
rows needed by BRUR domains from a rich, regenerable GDAL OSM GeoPackage into
small per-domain SQLite files without decoding geometry or OSM tags in Python.
Downstream BRUR normalization is a separate phase.
"""
from __future__ import annotations

import argparse
import json
import os
import sqlite3
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

from source_identity import compute_source_identity

STAGE_FORMAT = "BOSG1"
STAGE_VERSION = 1
ALL_DOMAINS = ("roads", "traffic", "pois", "addresses", "areas", "coastline")
SOURCE_LAYERS = ("points", "lines", "multilinestrings", "multipolygons", "other_relations")


def _now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def _log(message: str) -> None:
    print(f"[{_now()}] [osm-gpkg-stage] {message}", flush=True)


def _quote(name: str) -> str:
    return '"' + name.replace('"', '""') + '"'


def _atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + f".tmp-{os.getpid()}")
    temp.write_text(json.dumps(value, indent=2, sort_keys=True), encoding="utf-8")
    temp.replace(path)


def _load_json(path: Path) -> dict:
    if not path.is_file():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def _table_exists(connection: sqlite3.Connection, table: str) -> bool:
    return connection.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)
    ).fetchone() is not None


def _columns(connection: sqlite3.Connection, table: str) -> set[str]:
    return {str(row[1]) for row in connection.execute(f"PRAGMA table_info({_quote(table)})")}


def _not_empty(column: str) -> str:
    q = _quote(column)
    return f"({q} IS NOT NULL AND TRIM(CAST({q} AS TEXT)) <> '')"


def _has_any(columns: set[str], names: Iterable[str]) -> str | None:
    parts = [_not_empty(name) for name in names if name in columns]
    return " OR ".join(parts) if parts else None


def _other_tags_contains(columns: set[str], key: str, value: str | None = None) -> str | None:
    if "other_tags" not in columns:
        return None
    needle = f'"{key}"=>"' if value is None else f'"{key}"=>"{value}"'
    return f"other_tags LIKE '%{needle.replace("'", "''")}%'"


def _or(*parts: str | None) -> str | None:
    values = [part for part in parts if part]
    return " OR ".join(f"({part})" for part in values) if values else None


def _predicate(domain: str, layer: str, columns: set[str]) -> str | None:
    if domain == "roads":
        if layer not in {"lines", "multilinestrings"}:
            return None
        return _or(
            _not_empty("highway") if "highway" in columns else None,
            _other_tags_contains(columns, "highway"),
        )

    if domain == "traffic":
        if layer != "points":
            return None
        explicit = "highway = 'traffic_signals'" if "highway" in columns else None
        return _or(explicit, _other_tags_contains(columns, "highway", "traffic_signals"))

    if domain == "pois":
        if layer not in {"points", "multipolygons", "other_relations"}:
            return None
        common = _has_any(columns, ("amenity", "shop", "tourism"))
        point_extra = _has_any(columns, ("railway",)) if layer == "points" else None
        speed_camera = "highway = 'speed_camera'" if layer == "points" and "highway" in columns else None
        fallback = _or(
            _other_tags_contains(columns, "amenity"),
            _other_tags_contains(columns, "shop"),
            _other_tags_contains(columns, "tourism"),
            _other_tags_contains(columns, "railway"),
            _other_tags_contains(columns, "highway", "speed_camera"),
        )
        return _or(common, point_extra, speed_camera, fallback)

    if domain == "addresses":
        explicit = _not_empty("addr_housenumber") if "addr_housenumber" in columns else None
        return _or(explicit, _other_tags_contains(columns, "addr:housenumber"))

    if domain == "areas":
        if layer != "multipolygons":
            return None
        explicit = _has_any(
            columns,
            (
                "building", "landuse", "natural", "amenity", "leisure", "tourism",
                "shop", "boundary", "place", "aeroway", "military", "historic",
                "man_made", "office", "craft", "geological",
            ),
        )
        fallback = _or(
            _other_tags_contains(columns, "building"),
            _other_tags_contains(columns, "landuse"),
            _other_tags_contains(columns, "natural"),
            _other_tags_contains(columns, "boundary"),
        )
        return _or(explicit, fallback)

    if domain == "coastline":
        if layer != "lines":
            return None
        explicit = "natural = 'coastline'" if "natural" in columns else None
        return _or(explicit, _other_tags_contains(columns, "natural", "coastline"))

    raise ValueError(f"unsupported source-stage domain: {domain}")


def _validate_gdal_osm_gpkg(gpkg: Path) -> None:
    source = sqlite3.connect(f"file:{gpkg}?mode=ro", uri=True)
    try:
        missing = [name for name in ("points", "lines", "multipolygons") if not _table_exists(source, name)]
    finally:
        source.close()
    if missing:
        raise ValueError(
            "GeoPackage is not a GDAL OSM source cache; missing layers: " + ", ".join(missing)
        )


def _stage_domain(gpkg: Path, destination: Path, domain: str) -> dict:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temp = destination.with_suffix(destination.suffix + f".tmp-{os.getpid()}-{time.time_ns()}")
    try:
        temp.unlink()
    except OSError:
        pass

    source = sqlite3.connect(f"file:{gpkg}?mode=ro", uri=True)
    layer_predicates: list[tuple[str, str]] = []
    try:
        for layer in SOURCE_LAYERS:
            if not _table_exists(source, layer):
                continue
            predicate = _predicate(domain, layer, _columns(source, layer))
            if predicate:
                layer_predicates.append((layer, predicate))
    finally:
        source.close()

    if not layer_predicates:
        raise ValueError(f"GeoPackage has no usable layers for domain={domain}")

    started = time.monotonic()
    target = sqlite3.connect(temp)
    counts: dict[str, int] = {}
    try:
        target.execute("PRAGMA journal_mode=OFF")
        target.execute("PRAGMA synchronous=OFF")
        target.execute("PRAGMA temp_store=MEMORY")
        target.execute("ATTACH DATABASE ? AS src", (str(gpkg),))
        target.execute(
            "CREATE TABLE brur_source_stage(format TEXT NOT NULL, version INTEGER NOT NULL, domain TEXT NOT NULL)"
        )
        target.execute("INSERT INTO brur_source_stage VALUES(?,?,?)", (STAGE_FORMAT, STAGE_VERSION, domain))
        for layer, predicate in layer_predicates:
            output_table = f"source_{layer}"
            _log(f"STAGE domain={domain} layer={layer}")
            target.execute(
                f"CREATE TABLE {_quote(output_table)} AS "
                f"SELECT * FROM src.{_quote(layer)} WHERE {predicate}"
            )
            count = int(target.execute(f"SELECT COUNT(*) FROM {_quote(output_table)}").fetchone()[0])
            counts[layer] = count
            _log(f"STAGE domain={domain} layer={layer} rows={count:,}")
        target.commit()
        target.execute("DETACH DATABASE src")
    except BaseException:
        target.close()
        try:
            temp.unlink()
        except OSError:
            pass
        raise
    target.close()
    temp.replace(destination)
    return {
        "complete": True,
        "layers": counts,
        "records": sum(counts.values()),
        "size_bytes": destination.stat().st_size,
        "elapsed_seconds": round(time.monotonic() - started, 3),
    }


def stage_osm_geopackage(
    gpkg: Path,
    stage_dir: Path,
    domains: Iterable[str] = ALL_DOMAINS,
) -> dict[str, Path]:
    """Write per-domain provider-stage files and stop before BRUR normalization."""
    if not gpkg.is_file():
        raise FileNotFoundError(gpkg)
    _validate_gdal_osm_gpkg(gpkg)
    requested = tuple(dict.fromkeys(domains))
    unknown = set(requested) - set(ALL_DOMAINS)
    if unknown:
        raise ValueError(f"unsupported source-stage domains: {', '.join(sorted(unknown))}")

    stage_dir.mkdir(parents=True, exist_ok=True)
    identity = compute_source_identity(gpkg, stage_dir / "source_identity.json")
    manifest_path = stage_dir / "manifest.json"
    old = _load_json(manifest_path)
    compatible = (
        old.get("format") == STAGE_FORMAT
        and old.get("version") == STAGE_VERSION
        and old.get("source") == identity
    )
    old_domains = old.get("domains", {}) if compatible and isinstance(old.get("domains"), dict) else {}
    manifest_domains: dict[str, dict] = dict(old_domains)
    outputs: dict[str, Path] = {}

    for domain in requested:
        path = stage_dir / f"{domain}.sqlite"
        entry = old_domains.get(domain)
        valid = (
            isinstance(entry, dict)
            and entry.get("complete") is True
            and path.is_file()
            and entry.get("size_bytes") == path.stat().st_size
        )
        if valid:
            _log(f"HIT domain={domain} rows={entry.get('records', '?')} bytes={path.stat().st_size:,}")
        else:
            report = _stage_domain(gpkg, path, domain)
            manifest_domains[domain] = report
            _atomic_json(
                manifest_path,
                {"format": STAGE_FORMAT, "version": STAGE_VERSION, "source": identity, "domains": manifest_domains},
            )
            _log(
                f"DONE domain={domain} rows={report['records']:,} bytes={report['size_bytes']:,} "
                f"elapsed={report['elapsed_seconds']:.3f}s"
            )
        outputs[domain] = path

    _atomic_json(
        manifest_path,
        {"format": STAGE_FORMAT, "version": STAGE_VERSION, "source": identity, "domains": manifest_domains},
    )
    return outputs


def main() -> None:
    parser = argparse.ArgumentParser(description="Stage BRUR source-domain files from a GDAL OSM GeoPackage")
    parser.add_argument("source", type=Path)
    parser.add_argument("--output", type=Path, required=True, help="source-stage output directory")
    parser.add_argument("--domain", default="all", help="comma-separated domains or all")
    args = parser.parse_args()
    if args.domain == "all":
        domains = ALL_DOMAINS
    else:
        domains = tuple(part.strip() for part in args.domain.split(",") if part.strip())
    outputs = stage_osm_geopackage(args.source, args.output, domains)
    for domain, path in outputs.items():
        _log(f"OUTPUT domain={domain} path={path} bytes={path.stat().st_size:,}")


if __name__ == "__main__":
    main()
