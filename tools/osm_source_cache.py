#!/usr/bin/env python3
"""Build reusable route-specific OSM caches from one authoritative source scan.

Dependencies:
- Reads OSM sources through pyosmium and source_identity.py.
- Writes deterministic local OSM XML caches consumed by existing offline builders.
- Owns source ingest/caching only; it does not own road, routing, feature, or search policy.
"""

from __future__ import annotations

import argparse
import json
import math
import pickle
import shutil
import tempfile
import time
from pathlib import Path
from typing import BinaryIO, Iterable, Iterator, TextIO
from xml.sax.saxutils import quoteattr

import osmium

from source_identity import compute_source_identity
from world_common import ensure_pbf

CACHE_FORMAT = "BOSC1"
CACHE_DIR_NAME = "osm_source_cache"
ROUTE_VERSIONS = {
    "highways": 1,
    "traffic_signals": 1,
    "pois": 1,
    "addresses": 1,
    "areas": 1,
}
ALL_ROUTES = tuple(ROUTE_VERSIONS)
NODE_PROGRESS_INTERVAL = 5_000_000
WAY_PROGRESS_INTERVAL = 250_000
RELATION_PROGRESS_INTERVAL = 50_000
NODE_BUCKETS = 64

POI_KEYS = {
    "amenity", "shop", "tourism", "leisure", "office", "healthcare", "emergency",
    "public_transport", "railway", "aeroway", "craft", "historic", "sport", "club",
    "man_made", "information", "advertising",
}
SPECIAL_HIGHWAY_POIS = {"speed_camera", "services", "rest_area", "bus_stop", "elevator"}
BACKGROUND_LANDUSE = {
    "reservoir", "forest", "farmland", "farmyard", "meadow", "grass", "orchard", "vineyard",
    "residential", "commercial", "industrial", "retail", "basin",
}
BACKGROUND_NATURAL = {"water", "wood", "bay", "strait"}


def _tags_dict(tags: osmium.osm.TagList) -> dict[str, str]:
    return {str(tag.k): str(tag.v) for tag in tags}


def _is_poi(tags: dict[str, str]) -> bool:
    if any(key in tags for key in POI_KEYS):
        return True
    if tags.get("highway") in SPECIAL_HIGHWAY_POIS:
        return True
    if "enforcement" in tags or "surveillance" in tags:
        return True
    return any(key.startswith("camera:") for key in tags)


def _is_address(tags: dict[str, str]) -> bool:
    return bool(tags.get("addr:housenumber") and (tags.get("addr:street") or tags.get("addr:place")))


def _is_area_candidate(tags: dict[str, str]) -> bool:
    if tags.get("building") is not None or tags.get("building:part") is not None:
        return True
    if _is_poi(tags):
        return True
    if tags.get("boundary") == "administrative" and tags.get("admin_level") == "2":
        return True
    if tags.get("natural") in BACKGROUND_NATURAL:
        return True
    if tags.get("landuse") in BACKGROUND_LANDUSE:
        return True
    if tags.get("waterway") == "riverbank" or tags.get("water") is not None:
        return True
    return False


def _source_matches(manifest: dict, source_identity: dict[str, object]) -> bool:
    source = manifest.get("source")
    return isinstance(source, dict) and source == source_identity


def _route_cache_valid(cache_dir: Path, manifest: dict, route: str) -> bool:
    routes = manifest.get("routes")
    if not isinstance(routes, dict):
        return False
    entry = routes.get(route)
    if not isinstance(entry, dict):
        return False
    if entry.get("version") != ROUTE_VERSIONS[route] or entry.get("complete") is not True:
        return False
    filename = entry.get("file")
    if not isinstance(filename, str) or not filename:
        return False
    path = cache_dir / filename
    if not path.is_file() or path.stat().st_size < 32:
        return False
    try:
        with path.open("rb") as handle:
            handle.seek(max(0, path.stat().st_size - 128))
            tail = handle.read()
    except OSError:
        return False
    return b"</osm>" in tail


def _load_manifest(path: Path) -> dict:
    if not path.is_file():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def _atomic_json(path: Path, value: dict) -> None:
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(value, indent=2, sort_keys=True), encoding="utf-8")
    temp.replace(path)


def _pickle_append(handle: BinaryIO, value: object) -> None:
    pickle.dump(value, handle, protocol=5)


def _pickle_iter(path: Path) -> Iterator[object]:
    if not path.is_file():
        return
    with path.open("rb") as handle:
        while True:
            try:
                yield pickle.load(handle)
            except EOFError:
                break


def _valid_location(node: osmium.osm.NodeRef) -> tuple[float, float] | None:
    if not node.location.valid():
        return None
    return float(node.lon), float(node.lat)


def _way_record(way: osmium.osm.Way, tags: dict[str, str]) -> tuple[int, list[tuple[int, float, float]], dict[str, str]]:
    nodes: list[tuple[int, float, float]] = []
    for ref in way.nodes:
        location = _valid_location(ref)
        if location is None:
            nodes.append((int(ref.ref), math.nan, math.nan))
        else:
            nodes.append((int(ref.ref), location[0], location[1]))
    return int(way.id), nodes, tags


def _relation_record(relation: osmium.osm.Relation, tags: dict[str, str]) -> tuple[int, list[tuple[str, int, str]], dict[str, str]]:
    members = [(str(member.type), int(member.ref), str(member.role)) for member in relation.members]
    return int(relation.id), members, tags


def _progress_count(current: int, total: int | None) -> str:
    if isinstance(total, int) and total >= current and total > 0:
        return f"{current:,} / {total:,}"
    return f"{current:,}"


class SourceCacheHandler(osmium.SimpleHandler):
    """Scan one OSM source and spool only facts needed to finalize stale routes."""

    def __init__(self, work_dir: Path, stale_routes: set[str], known_totals: dict[str, int]) -> None:
        super().__init__()
        self.work_dir = work_dir
        self.stale_routes = stale_routes
        self.known_totals = known_totals
        self.counts = {"nodes": 0, "ways": 0, "relations": 0}
        self.started = time.perf_counter()
        self.signal_ids: set[int] = set()
        self.area_relation_way_ids: set[int] = set()
        self._handles: dict[str, BinaryIO] = {}

    def _handle(self, name: str) -> BinaryIO:
        handle = self._handles.get(name)
        if handle is None:
            handle = (self.work_dir / f"{name}.pkl").open("ab")
            self._handles[name] = handle
        return handle

    def close(self) -> None:
        for handle in self._handles.values():
            handle.close()
        self._handles.clear()

    def _print_progress(self, kind: str, interval: int) -> None:
        current = self.counts[kind]
        if current == 0 or current % interval != 0:
            return
        elapsed = max(0.001, time.perf_counter() - self.started)
        print(
            f"[osm-source] {kind}: {_progress_count(current, self.known_totals.get(kind))} | "
            f"{current / elapsed:,.0f}/s",
            flush=True,
        )

    def node(self, node: osmium.osm.Node) -> None:
        self.counts["nodes"] += 1
        self._print_progress("nodes", NODE_PROGRESS_INTERVAL)
        if not node.location.valid():
            return
        tags = _tags_dict(node.tags)
        record = (int(node.id), float(node.lon), float(node.lat), tags)
        if "traffic_signals" in self.stale_routes and tags.get("highway") == "traffic_signals":
            self.signal_ids.add(int(node.id))
            _pickle_append(self._handle("traffic_signal_nodes"), record)
        if "pois" in self.stale_routes and _is_poi(tags):
            _pickle_append(self._handle("poi_nodes"), record)
        if "addresses" in self.stale_routes and _is_address(tags):
            _pickle_append(self._handle("address_nodes"), record)

    def way(self, way: osmium.osm.Way) -> None:
        self.counts["ways"] += 1
        self._print_progress("ways", WAY_PROGRESS_INTERVAL)
        tags = _tags_dict(way.tags)
        needs_spool = False
        if "areas" in self.stale_routes:
            needs_spool = True
        elif "highways" in self.stale_routes and tags.get("highway"):
            needs_spool = True
        elif "traffic_signals" in self.stale_routes and tags.get("highway"):
            needs_spool = any(int(ref.ref) in self.signal_ids for ref in way.nodes)
        elif "pois" in self.stale_routes and _is_poi(tags):
            needs_spool = True
        elif "addresses" in self.stale_routes and _is_address(tags):
            needs_spool = True
        if needs_spool:
            _pickle_append(self._handle("ways"), _way_record(way, tags))

    def relation(self, relation: osmium.osm.Relation) -> None:
        self.counts["relations"] += 1
        self._print_progress("relations", RELATION_PROGRESS_INTERVAL)
        if "areas" not in self.stale_routes:
            return
        tags = _tags_dict(relation.tags)
        relation_type = tags.get("type")
        if relation_type not in {"multipolygon", "boundary"} and not _is_area_candidate(tags):
            return
        record = _relation_record(relation, tags)
        _pickle_append(self._handle("area_relations"), record)
        for member_type, member_ref, _role in record[1]:
            if member_type == "w":
                self.area_relation_way_ids.add(member_ref)


class _RouteWriter:
    """Collect selected route facts and atomically publish one OSM XML cache."""

    def __init__(self, route: str, work_dir: Path, destination: Path) -> None:
        self.route = route
        self.work_dir = work_dir / f"route-{route}"
        self.work_dir.mkdir(parents=True, exist_ok=True)
        self.destination = destination
        self.ways_path = self.work_dir / "ways.xml"
        self.relations_path = self.work_dir / "relations.xml"
        self.ways_file: TextIO = self.ways_path.open("w", encoding="utf-8")
        self.relations_file: TextIO = self.relations_path.open("w", encoding="utf-8")
        self.bucket_handles: dict[int, BinaryIO] = {}
        self.counts = {"nodes": 0, "ways": 0, "relations": 0}

    def _bucket(self, node_id: int) -> BinaryIO:
        bucket = node_id % NODE_BUCKETS
        handle = self.bucket_handles.get(bucket)
        if handle is None:
            handle = (self.work_dir / f"nodes-{bucket:02d}.pkl").open("ab")
            self.bucket_handles[bucket] = handle
        return handle

    def add_node(self, node_id: int, lon: float, lat: float, tags: dict[str, str] | None = None) -> None:
        if not math.isfinite(lon) or not math.isfinite(lat):
            return
        _pickle_append(self._bucket(node_id), (node_id, lon, lat, tags or {}))

    def add_way(self, record: tuple[int, list[tuple[int, float, float]], dict[str, str]]) -> None:
        way_id, nodes, tags = record
        for node_id, lon, lat in nodes:
            self.add_node(node_id, lon, lat)
        self.ways_file.write(f"  <way id={quoteattr(str(way_id))}>\n")
        for node_id, _lon, _lat in nodes:
            self.ways_file.write(f"    <nd ref={quoteattr(str(node_id))}/>\n")
        _write_tags(self.ways_file, tags, "    ")
        self.ways_file.write("  </way>\n")
        self.counts["ways"] += 1

    def add_relation(self, record: tuple[int, list[tuple[str, int, str]], dict[str, str]]) -> None:
        relation_id, members, tags = record
        self.relations_file.write(f"  <relation id={quoteattr(str(relation_id))}>\n")
        type_map = {"n": "node", "w": "way", "r": "relation"}
        for member_type, member_ref, role in members:
            xml_type = type_map.get(member_type, member_type)
            self.relations_file.write(
                f"    <member type={quoteattr(xml_type)} ref={quoteattr(str(member_ref))} role={quoteattr(role)}/>\n"
            )
        _write_tags(self.relations_file, tags, "    ")
        self.relations_file.write("  </relation>\n")
        self.counts["relations"] += 1

    def close_inputs(self) -> None:
        self.ways_file.close()
        self.relations_file.close()
        for handle in self.bucket_handles.values():
            handle.close()
        self.bucket_handles.clear()

    def publish(self) -> dict[str, int]:
        self.close_inputs()
        temp = self.destination.with_suffix(self.destination.suffix + ".tmp")
        with temp.open("w", encoding="utf-8") as output:
            output.write('<?xml version="1.0" encoding="UTF-8"?>\n')
            output.write('<osm version="0.6" generator="brur-world-osm-source-cache">\n')
            for bucket in range(NODE_BUCKETS):
                bucket_path = self.work_dir / f"nodes-{bucket:02d}.pkl"
                if not bucket_path.is_file():
                    continue
                unique: dict[int, tuple[float, float, dict[str, str]]] = {}
                for raw in _pickle_iter(bucket_path):
                    node_id, lon, lat, tags = raw
                    current = unique.get(node_id)
                    if current is None or tags:
                        unique[node_id] = (lon, lat, tags)
                for node_id, (lon, lat, tags) in unique.items():
                    output.write(
                        f"  <node id={quoteattr(str(node_id))} lon={quoteattr(repr(lon))} lat={quoteattr(repr(lat))}"
                    )
                    if not tags:
                        output.write("/>\n")
                    else:
                        output.write(">\n")
                        _write_tags(output, tags, "    ")
                        output.write("  </node>\n")
                    self.counts["nodes"] += 1
            _copy_text(self.ways_path, output)
            _copy_text(self.relations_path, output)
            output.write("</osm>\n")
        temp.replace(self.destination)
        return dict(self.counts)


def _write_tags(output: TextIO, tags: dict[str, str], indent: str) -> None:
    for key, value in tags.items():
        output.write(f"{indent}<tag k={quoteattr(str(key))} v={quoteattr(str(value))}/>\n")


def _copy_text(path: Path, output: TextIO) -> None:
    if not path.is_file():
        return
    with path.open("r", encoding="utf-8") as source:
        shutil.copyfileobj(source, output, length=1024 * 1024)


def _load_standalone_nodes(path: Path, writer: _RouteWriter) -> None:
    for raw in _pickle_iter(path):
        node_id, lon, lat, tags = raw
        writer.add_node(int(node_id), float(lon), float(lat), dict(tags))


def _select_way(route: str, record, signal_ids: set[int], area_relation_way_ids: set[int]) -> bool:
    way_id, nodes, tags = record
    if route == "highways":
        return bool(tags.get("highway"))
    if route == "traffic_signals":
        return bool(tags.get("highway")) and any(node_id in signal_ids for node_id, _lon, _lat in nodes)
    if route == "pois":
        return _is_poi(tags)
    if route == "addresses":
        return _is_address(tags)
    if route == "areas":
        return int(way_id) in area_relation_way_ids or _is_area_candidate(tags)
    return False


def _known_totals(manifest: dict, source_identity: dict[str, object]) -> dict[str, int]:
    if not _source_matches(manifest, source_identity):
        return {}
    raw = manifest.get("source_scan")
    if not isinstance(raw, dict):
        return {}
    result: dict[str, int] = {}
    for key in ("nodes", "ways", "relations"):
        value = raw.get(key)
        if isinstance(value, int) and value >= 0:
            result[key] = value
    return result


def build_source_caches(source: Path, cache_dir: Path, routes: Iterable[str] = ALL_ROUTES) -> dict[str, Path]:
    """Ensure requested route caches exist, rebuilding all stale routes in one source traversal."""
    ensure_pbf(source)
    requested = tuple(dict.fromkeys(routes))
    unknown = sorted(set(requested) - set(ROUTE_VERSIONS))
    if unknown:
        raise ValueError(f"Unknown OSM source-cache routes: {', '.join(unknown)}")
    cache_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = cache_dir / "manifest.json"
    manifest = _load_manifest(manifest_path)
    source_identity = compute_source_identity(source)
    same_source = _source_matches(manifest, source_identity)
    stale = {
        route for route in requested
        if not same_source or not _route_cache_valid(cache_dir, manifest, route)
    }
    if not stale:
        print(f"[osm-source] reuse {len(requested)} route cache(s): {', '.join(requested)}", flush=True)
        return {route: cache_dir / f"{route}.osm" for route in requested}

    known_totals = _known_totals(manifest, source_identity)
    print(
        f"[osm-source] scan once for stale routes: {', '.join(sorted(stale))} | source={source}",
        flush=True,
    )
    started = time.perf_counter()
    with tempfile.TemporaryDirectory(prefix="brur-osm-source-", dir=cache_dir) as temp_name:
        work_dir = Path(temp_name)
        handler = SourceCacheHandler(work_dir, stale, known_totals)
        try:
            handler.apply_file(str(source), locations=True)
        finally:
            handler.close()

        writers = {
            route: _RouteWriter(route, work_dir, cache_dir / f"{route}.osm")
            for route in stale
        }
        if "traffic_signals" in writers:
            _load_standalone_nodes(work_dir / "traffic_signal_nodes.pkl", writers["traffic_signals"])
        if "pois" in writers:
            _load_standalone_nodes(work_dir / "poi_nodes.pkl", writers["pois"])
        if "addresses" in writers:
            _load_standalone_nodes(work_dir / "address_nodes.pkl", writers["addresses"])

        ways_path = work_dir / "ways.pkl"
        if ways_path.is_file():
            for raw in _pickle_iter(ways_path):
                record = raw
                for route, writer in writers.items():
                    if _select_way(route, record, handler.signal_ids, handler.area_relation_way_ids):
                        writer.add_way(record)

        if "areas" in writers:
            for raw in _pickle_iter(work_dir / "area_relations.pkl"):
                writers["areas"].add_relation(raw)

        route_counts: dict[str, dict[str, int]] = {}
        for route, writer in writers.items():
            route_counts[route] = writer.publish()

    previous_routes = manifest.get("routes") if same_source and isinstance(manifest.get("routes"), dict) else {}
    route_manifest = dict(previous_routes)
    for route in stale:
        route_manifest[route] = {
            "version": ROUTE_VERSIONS[route],
            "file": f"{route}.osm",
            "complete": True,
            "records": route_counts[route],
        }
    new_manifest = {
        "format": CACHE_FORMAT,
        "source": source_identity,
        "source_scan": handler.counts,
        "routes": route_manifest,
    }
    _atomic_json(manifest_path, new_manifest)
    elapsed = time.perf_counter() - started
    print(
        f"[osm-source] complete in {elapsed:.1f}s | nodes={handler.counts['nodes']:,} "
        f"ways={handler.counts['ways']:,} relations={handler.counts['relations']:,}",
        flush=True,
    )
    for route in sorted(stale):
        counts = route_counts[route]
        print(
            f"[osm-source] {route}: nodes={counts['nodes']:,} ways={counts['ways']:,} "
            f"relations={counts['relations']:,}",
            flush=True,
        )
    return {route: cache_dir / f"{route}.osm" for route in requested}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Path to authoritative Sweden .osm.pbf (or tiny .osm fixture)")
    parser.add_argument("--cache-dir", type=Path, default=Path("world_data") / CACHE_DIR_NAME)
    parser.add_argument(
        "--routes",
        default="all",
        help=f"Comma-separated route names or 'all' ({', '.join(ALL_ROUTES)})",
    )
    args = parser.parse_args()
    routes = ALL_ROUTES if args.routes == "all" else tuple(part.strip() for part in args.routes.split(",") if part.strip())
    build_source_caches(args.source, args.cache_dir, routes)


if __name__ == "__main__":
    main()
