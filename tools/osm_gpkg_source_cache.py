#!/usr/bin/env python3
"""Normalize a BRUR GDAL/OSM GeoPackage directly into portable source facts.

The authoritative raw input remains the OSM PBF.  `sweden-brur.gpkg` is a
regenerable provider/source cache produced from that PBF with GDAL and
`brur_osmconf.ini`.  This adapter reads the GeoPackage directly: there is no
second set of per-domain SQLite stage files and the PBF is never reparsed here.

Both the GeoPackage and its authoritative PBF are hashed and recorded as one
composite source identity.  The metadata-backed identity cache in
`source_identity.py` keeps unchanged warm runs cheap while preserving exact
SHA256+size identities.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import sqlite3
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, Iterator

from shapely import from_wkb

from area_source_cache import (
    FOOTER as BAF_FOOTER,
    FOOTER_MAGIC as BAF_FOOTER_MAGIC,
    FRAME as BAF_FRAME,
    HEADER as BAF_HEADER,
    MAGIC as BAF_MAGIC,
    RECORD_AREA_RELATION,
    RECORD_AREA_WAY,
    VERSION as BAF_VERSION,
    _encode_area,
    _encode_coastline,
    area_source_cache_metadata,
    is_area_candidate_tags,
    is_poi_tags,
)
from highway_facts import HighwayFactWriter, validate_highways
from normalized_source_facts import FactWriter, validate as validate_facts
from source_identity import compute_source_identity
from world_common import project

CACHE_FORMAT = "BOSC6-GDAL-OSM-GPKG"
EXTRACTOR_VERSION = 3
ROUTE_VERSIONS = {"highways": 7, "pois": 6, "addresses": 6, "traffic_signals": 6, "areas": 4}
ALL_ROUTES = tuple(ROUTE_VERSIONS)
SCHEMAS = {"pois": 1, "addresses": 1, "traffic_signals": 1}
PROGRESS_INTERVAL = 250_000
ADDRESS_TAGS = ("addr:housenumber", "addr:street", "addr:place", "addr:postcode", "addr:city", "addr:suburb")
PROMOTED_TAGS = {
    "name": "name", "barrier": "barrier", "highway": "highway", "ref": "ref",
    "address": "address", "is_in": "is_in", "place": "place", "man_made": "man_made",
    "amenity": "amenity", "shop": "shop", "tourism": "tourism", "railway": "railway",
    "waterway": "waterway", "aerialway": "aerialway", "natural": "natural", "surface": "surface",
    "lanes": "lanes", "maxspeed": "maxspeed", "oneway": "oneway", "bridge": "bridge",
    "tunnel": "tunnel", "layer": "layer", "type": "type", "aeroway": "aeroway",
    "admin_level": "admin_level", "boundary": "boundary", "building": "building",
    "building_levels": "building:levels", "height": "height", "craft": "craft",
    "geological": "geological", "historic": "historic", "land_area": "land_area",
    "landuse": "landuse", "leisure": "leisure", "military": "military", "office": "office",
    "sport": "sport", "addr_housenumber": "addr:housenumber", "addr_street": "addr:street",
    "addr_place": "addr:place", "addr_postcode": "addr:postcode", "addr_city": "addr:city",
    "addr_suburb": "addr:suburb",
}
_HSTORE = re.compile(r'"((?:[^"\\]|\\.)*)"=>"((?:[^"\\]|\\.)*)"')


def _now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def _log(message: str) -> None:
    print(f"[{_now()}] [osm-gpkg-source] {message}", flush=True)


def _atomic_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + f".tmp-{os.getpid()}")
    temp.write_text(json.dumps(value, indent=2, sort_keys=True), encoding="utf-8")
    temp.replace(path)


def _load_json(path: Path) -> dict:
    if not path.is_file(): return {}
    try: value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError): return {}
    return value if isinstance(value, dict) else {}


def _route_filename(route: str) -> str:
    return "areas.baf" if route == "areas" else f"{route}.brfacts"


def _route_metadata(path: Path, route: str) -> dict:
    if route == "areas": return area_source_cache_metadata(path)
    if route == "highways": return validate_highways(path)
    return validate_facts(path, SCHEMAS[route])


def _route_valid(cache_dir: Path, route: str, entry: object, source_identity: dict) -> bool:
    if not isinstance(entry, dict): return False
    if entry.get("version") != ROUTE_VERSIONS[route] or entry.get("extractor_version") != EXTRACTOR_VERSION: return False
    if entry.get("complete") is not True or entry.get("file") != _route_filename(route): return False
    if entry.get("source_identity") != source_identity: return False
    path = cache_dir / _route_filename(route)
    if not path.is_file() or entry.get("size_bytes") != path.stat().st_size: return False
    try: metadata = _route_metadata(path, route)
    except (OSError, ValueError, TypeError, KeyError): return False
    return str(metadata.get("sha256", "")) == entry.get("sha256")


def _table_exists(connection: sqlite3.Connection, table: str) -> bool:
    return connection.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (table,)).fetchone() is not None


def _validate_source(gpkg: Path) -> None:
    db = sqlite3.connect(f"file:{gpkg}?mode=ro", uri=True)
    try:
        missing = [name for name in ("points", "lines", "multipolygons") if not _table_exists(db, name)]
    finally: db.close()
    if missing: raise ValueError("not a BRUR GDAL/OSM GeoPackage; missing layers: " + ", ".join(missing))


def _gpkg_wkb(blob) -> bytes:
    raw = bytes(blob)
    if len(raw) < 8 or raw[:2] != b"GP": raise ValueError("invalid GeoPackage geometry header")
    envelope = (raw[3] >> 1) & 0x07
    envelope_bytes = {0: 0, 1: 32, 2: 48, 3: 48, 4: 64}.get(envelope)
    if envelope_bytes is None: raise ValueError(f"unsupported GeoPackage envelope code: {envelope}")
    offset = 8 + envelope_bytes
    if offset >= len(raw): raise ValueError("truncated GeoPackage geometry")
    return raw[offset:]


def _geometry(blob): return from_wkb(_gpkg_wkb(blob))


def _iter_lines(geometry) -> Iterator:
    if geometry is None or geometry.is_empty: return
    if geometry.geom_type == "LineString": yield geometry
    elif geometry.geom_type == "MultiLineString": yield from geometry.geoms
    elif geometry.geom_type == "GeometryCollection":
        for child in geometry.geoms: yield from _iter_lines(child)


def _iter_polygons(geometry) -> Iterator:
    if geometry is None or geometry.is_empty: return
    if geometry.geom_type == "Polygon": yield geometry
    elif geometry.geom_type == "MultiPolygon": yield from geometry.geoms
    elif geometry.geom_type == "GeometryCollection":
        for child in geometry.geoms: yield from _iter_polygons(child)


def _unescape_hstore(value: str) -> str:
    return value.replace('\\"', '"').replace('\\\\', '\\')


def _parse_other_tags(value) -> dict[str, str]:
    if not value: return {}
    text = str(value)
    return {_unescape_hstore(k): _unescape_hstore(v) for k, v in _HSTORE.findall(text)}


def _row_tags(row: sqlite3.Row) -> dict[str, str]:
    keys = set(row.keys()); tags = _parse_other_tags(row["other_tags"] if "other_tags" in keys else None)
    for column, tag in PROMOTED_TAGS.items():
        if column not in keys or row[column] in (None, ""): continue
        tags[tag] = str(row[column])
    return tags


def _row_identity(row: sqlite3.Row) -> tuple[str, int]:
    keys = set(row.keys())
    if "osm_way_id" in keys and row["osm_way_id"] not in (None, ""):
        return "way", int(str(row["osm_way_id"]).strip())
    if "osm_id" not in keys or row["osm_id"] in (None, ""):
        raise ValueError("OSM GeoPackage row has no osm_id/osm_way_id")
    value = int(str(row["osm_id"]).strip())
    return ("relation" if "osm_way_id" in keys else "way"), abs(value)


def _qcoord(lon: float, lat: float) -> tuple[int, int]:
    return int(round(lon * 10_000_000.0)), int(round(lat * 10_000_000.0))


def _synthetic_node_id(lon: float, lat: float, separation: str = "") -> int:
    qlon, qlat = _qcoord(lon, lat)
    digest = hashlib.blake2b(f"{qlon}:{qlat}:{separation}".encode("utf-8"), digest_size=8, person=b"brurroad").digest()
    return int.from_bytes(digest, "little", signed=False) & 0x7FFF_FFFF_FFFF_FFFF


def _separation(tags: dict[str, str]) -> str:
    return f"l={tags.get('layer','0')};b={tags.get('bridge','')};t={tags.get('tunnel','')}" if tags.get("bridge") not in (None, "", "no", "0") or tags.get("tunnel") not in (None, "", "no", "0") or tags.get("layer") else ""


def _signal_points(gpkg: Path) -> tuple[list[dict], dict[tuple[int, int], list[int]]]:
    db = sqlite3.connect(f"file:{gpkg}?mode=ro", uri=True); db.row_factory = sqlite3.Row
    signals: list[dict] = []; by_coord: dict[tuple[int, int], list[int]] = {}
    try:
        for row in db.execute("SELECT * FROM points"):
            tags = _row_tags(row)
            if tags.get("highway") != "traffic_signals": continue
            geom = _geometry(row["geom"])
            if geom.geom_type != "Point": continue
            _, osm_id = _row_identity(row); lon = float(geom.x); lat = float(geom.y); index = len(signals)
            signals.append({"osm_id": osm_id, "lon": lon, "lat": lat, "tags": tags, "way_ids": set()})
            by_coord.setdefault(_qcoord(lon, lat), []).append(index)
    finally: db.close()
    return signals, by_coord


def _scan_roads(gpkg: Path, destination: Path | None, need_signals: bool) -> tuple[dict | None, list[dict]]:
    signals: list[dict] = []; signal_by_coord: dict[tuple[int, int], list[int]] = {}
    if need_signals: signals, signal_by_coord = _signal_points(gpkg)
    writer = HighwayFactWriter(destination) if destination is not None else None
    db = sqlite3.connect(f"file:{gpkg}?mode=ro", uri=True); db.row_factory = sqlite3.Row; ways = 0
    try:
        for row in db.execute("SELECT * FROM lines"):
            tags = _row_tags(row)
            if not tags.get("highway"): continue
            _, way_id = _row_identity(row); geometry = _geometry(row["geom"])
            for line in _iter_lines(geometry):
                coords = [(float(p[0]), float(p[1])) for p in line.coords]
                if len(coords) < 2: continue
                sep = _separation(tags); last = len(coords) - 1; node_ids = []
                for index, (lon, lat) in enumerate(coords):
                    node_ids.append(_synthetic_node_id(lon, lat, sep if sep and index not in {0, last} else ""))
                    for signal_index in signal_by_coord.get(_qcoord(lon, lat), ()):
                        signals[signal_index]["way_ids"].add(way_id)
                if writer is not None: writer.write_way(way_id, node_ids, coords, tags)
                ways += 1
                if ways % PROGRESS_INTERVAL == 0: _log(f"NORMALIZE highways={ways:,}")
        report = writer.publish() if writer is not None else None
    except BaseException:
        if writer is not None: writer.abort()
        raise
    finally: db.close()
    return report, signals


def _normalize_signals(signals: list[dict], destination: Path) -> dict:
    writer = FactWriter(destination, SCHEMAS["traffic_signals"])
    try:
        for signal in signals:
            writer.write({"osm_id": int(signal["osm_id"]), "lon": float(signal["lon"]), "lat": float(signal["lat"]), "tags": signal["tags"], "way_ids": sorted(int(v) for v in signal["way_ids"])})
        return writer.publish()
    except BaseException: writer.abort(); raise


def _point_or_centroid(geometry) -> tuple[float, float]:
    point = geometry if geometry.geom_type == "Point" else geometry.centroid
    return project(float(point.x), float(point.y))


def _poi_geometry(geometry) -> list[list[list[float]]] | None:
    polygons = []
    for polygon in _iter_polygons(geometry):
        polygons.append([[*project(float(p[0]), float(p[1]))] for p in polygon.exterior.coords])
    return polygons or None


def _normalize_pois(gpkg: Path, destination: Path) -> dict:
    writer = FactWriter(destination, SCHEMAS["pois"]); db = sqlite3.connect(f"file:{gpkg}?mode=ro", uri=True); db.row_factory = sqlite3.Row; records = 0
    try:
        for layer in ("points", "multipolygons", "other_relations"):
            if not _table_exists(db, layer): continue
            for row in db.execute(f'SELECT * FROM "{layer}"'):
                tags = _row_tags(row)
                if not is_poi_tags(tags): continue
                geometry = _geometry(row["geom"]); osm_type, osm_id = _row_identity(row); x, y = _point_or_centroid(geometry)
                fact = {"osm_type": "node" if layer == "points" else osm_type, "osm_id": osm_id, "x": x, "y": y, "tags": tags}
                polygons = _poi_geometry(geometry)
                if polygons: fact["geometry"] = polygons
                writer.write(fact); records += 1
            _log(f"NORMALIZE pois layer={layer} records={records:,}")
        return writer.publish()
    except BaseException: writer.abort(); raise
    finally: db.close()


def _normalize_addresses(gpkg: Path, destination: Path) -> dict:
    writer = FactWriter(destination, SCHEMAS["addresses"]); db = sqlite3.connect(f"file:{gpkg}?mode=ro", uri=True); db.row_factory = sqlite3.Row; records = 0
    try:
        for layer in ("points", "lines", "multilinestrings", "multipolygons", "other_relations"):
            if not _table_exists(db, layer): continue
            for row in db.execute(f'SELECT * FROM "{layer}"'):
                tags = _row_tags(row); number = str(tags.get("addr:housenumber", "")).strip(); street = str(tags.get("addr:street") or tags.get("addr:place") or "").strip()
                if not number or not street: continue
                geometry = _geometry(row["geom"]); osm_type, osm_id = _row_identity(row); x, y = _point_or_centroid(geometry)
                values = {key: str(tags[key]) for key in ADDRESS_TAGS if key in tags}
                writer.write({"osm_type": "node" if layer == "points" else osm_type, "osm_id": osm_id, "x": x, "y": y, "tags": values}); records += 1
            _log(f"NORMALIZE addresses layer={layer} records={records:,}")
        return writer.publish()
    except BaseException: writer.abort(); raise
    finally: db.close()


def _polygon_fact_geometry(geometry) -> list[dict]:
    result = []
    for polygon in _iter_polygons(geometry):
        outer = [[*project(float(p[0]), float(p[1]))] for p in list(polygon.exterior.coords)[:-1]]
        holes = [[[ *project(float(p[0]), float(p[1]))] for p in list(ring.coords)[:-1]] for ring in polygon.interiors]
        if len(outer) >= 3: result.append({"outer": outer, "holes": [hole for hole in holes if len(hole) >= 3]})
    return result


class _AreaWriter:
    def __init__(self, destination: Path) -> None:
        self.destination = destination; destination.parent.mkdir(parents=True, exist_ok=True)
        self.temp = destination.with_suffix(destination.suffix + f".tmp-{os.getpid()}-{time.time_ns()}")
        self.handle = self.temp.open("wb"); self.digest = hashlib.sha256(); self.records = 0; self.payload_bytes = 0
        header = BAF_HEADER.pack(BAF_MAGIC, BAF_VERSION); self.handle.write(header); self.digest.update(header)
    def write_payload(self, payload: bytes) -> None:
        framed = BAF_FRAME.pack(len(payload)) + payload; self.handle.write(framed); self.digest.update(framed); self.payload_bytes += len(framed); self.records += 1
    def publish(self) -> dict:
        digest = self.digest.digest(); self.handle.write(BAF_FOOTER.pack(BAF_FOOTER_MAGIC, self.records, self.payload_bytes, digest)); self.handle.flush(); os.fsync(self.handle.fileno()); self.handle.close(); self.temp.replace(self.destination)
        return {"records": self.records, "size_bytes": self.destination.stat().st_size, "sha256": digest.hex()}
    def abort(self) -> None:
        try: self.handle.close()
        except Exception: pass
        try: self.temp.unlink()
        except OSError: pass


def _normalize_areas(gpkg: Path, destination: Path) -> dict:
    writer = _AreaWriter(destination); db = sqlite3.connect(f"file:{gpkg}?mode=ro", uri=True); db.row_factory = sqlite3.Row; records = 0; coastlines = 0
    try:
        for row in db.execute("SELECT * FROM multipolygons"):
            tags = _row_tags(row)
            if not is_area_candidate_tags(tags): continue
            polygons = _polygon_fact_geometry(_geometry(row["geom"]))
            if not polygons: continue
            osm_type, osm_id = _row_identity(row); record_type = RECORD_AREA_RELATION if osm_type == "relation" else RECORD_AREA_WAY
            writer.write_payload(_encode_area(record_type, osm_id, osm_id, tags, polygons)); records += 1
            if records % PROGRESS_INTERVAL == 0: _log(f"NORMALIZE areas={records:,}")
        for row in db.execute("SELECT * FROM lines"):
            tags = _row_tags(row)
            if tags.get("natural") != "coastline": continue
            _, osm_id = _row_identity(row)
            for line in _iter_lines(_geometry(row["geom"])):
                points = [project(float(p[0]), float(p[1])) for p in line.coords]
                if len(points) >= 2: writer.write_payload(_encode_coastline(osm_id, points)); coastlines += 1
        _log(f"NORMALIZE areas records={records:,} coastlines={coastlines:,}")
        return writer.publish()
    except BaseException: writer.abort(); raise
    finally: db.close()


def _composite_identity(gpkg_identity: dict, pbf_identity: dict) -> dict:
    sources = {"brur_gpkg": gpkg_identity, "osm_pbf": pbf_identity}
    digest = hashlib.sha256(json.dumps(sources, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
    return {"algorithm": "sha256-composite", "digest": digest, "sources": sources}


def _entry(route: str, report: dict, path: Path, source_identity: dict, elapsed: float) -> dict:
    return {"version": ROUTE_VERSIONS[route], "extractor_version": EXTRACTOR_VERSION, "extractor": "gdal-osm-gpkg-direct", "complete": True, "file": _route_filename(route), "records": int(report.get("records", 0)), "size_bytes": int(path.stat().st_size), "sha256": str(report["sha256"]), "source_identity": source_identity, "elapsed_seconds": round(elapsed, 3)}


def build_osm_gpkg_source_caches(gpkg: Path, source_pbf: Path, cache_dir: Path, routes: Iterable[str] = ALL_ROUTES) -> dict[str, Path]:
    requested = tuple(dict.fromkeys(routes)); unknown = sorted(set(requested) - set(ALL_ROUTES))
    if unknown: raise ValueError(f"unknown GeoPackage source route(s): {', '.join(unknown)}")
    if not gpkg.is_file(): raise FileNotFoundError(gpkg)
    if not source_pbf.is_file(): raise FileNotFoundError(source_pbf)
    _validate_source(gpkg); cache_dir.mkdir(parents=True, exist_ok=True)

    gpkg_identity = compute_source_identity(gpkg, cache_dir / "gpkg_identity.json")
    pbf_identity = compute_source_identity(source_pbf, cache_dir / "pbf_identity.json")
    source_identity = _composite_identity(gpkg_identity, pbf_identity)
    manifest_path = cache_dir / "manifest.json"; old = _load_json(manifest_path)
    old_routes = old.get("routes", {}) if isinstance(old.get("routes"), dict) else {}
    entries = {route: dict(entry) for route, entry in old_routes.items() if route in ROUTE_VERSIONS and isinstance(entry, dict)}
    stale = {route for route in requested if not _route_valid(cache_dir, route, entries.get(route), source_identity)}
    run = {"format": CACHE_FORMAT, "status": "RUNNING", "started_at": _now(), "requested": list(requested), "source": source_identity, "blocks": {}}
    for route in requested:
        run["blocks"][route] = {"status": "REBUILD" if route in stale else "CACHE HIT"}; _log(f"PLAN route={route} status={run['blocks'][route]['status']}")
    _atomic_json(cache_dir / "last_run.json", run)
    if not stale:
        run.update({"status": "DONE", "completed_at": _now()}); _atomic_json(cache_dir / "last_run.json", run)
        return {route: cache_dir / _route_filename(route) for route in requested}

    signals = None
    if stale & {"highways", "traffic_signals"}:
        started = time.monotonic(); report, signals = _scan_roads(gpkg, cache_dir / "highways.brfacts" if "highways" in stale else None, "traffic_signals" in stale); elapsed = time.monotonic() - started
        if "highways" in stale:
            assert report is not None; path = cache_dir / "highways.brfacts"; entries["highways"] = _entry("highways", report, path, source_identity, elapsed); run["blocks"]["highways"] = {"status": "DONE", **entries["highways"]}
    if "traffic_signals" in stale:
        assert signals is not None; started = time.monotonic(); report = _normalize_signals(signals, cache_dir / "traffic_signals.brfacts"); elapsed = time.monotonic() - started; path = cache_dir / "traffic_signals.brfacts"; entries["traffic_signals"] = _entry("traffic_signals", report, path, source_identity, elapsed); run["blocks"]["traffic_signals"] = {"status": "DONE", **entries["traffic_signals"]}
    for route, builder in (("pois", _normalize_pois), ("addresses", _normalize_addresses), ("areas", _normalize_areas)):
        if route not in stale: continue
        started = time.monotonic(); path = cache_dir / _route_filename(route); report = builder(gpkg, path); elapsed = time.monotonic() - started; entries[route] = _entry(route, report, path, source_identity, elapsed); run["blocks"][route] = {"status": "DONE", **entries[route]}
        _atomic_json(cache_dir / "last_run.json", run)

    _atomic_json(manifest_path, {"format": CACHE_FORMAT, "source": source_identity, "routes": entries})
    run.update({"status": "DONE", "completed_at": _now()}); _atomic_json(cache_dir / "last_run.json", run)
    return {route: cache_dir / _route_filename(route) for route in requested}
