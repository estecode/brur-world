#!/usr/bin/env python3
"""Build reusable route-specific OSM caches from one authoritative source scan.

Dependencies:
- Reads OSM sources through pyosmium and source_identity.py.
- Writes deterministic local OSM XML caches consumed by existing offline builders.
- Owns source ingest/caching only; it does not own road, routing, feature, or search policy.
"""

from __future__ import annotations

import argparse
from collections import OrderedDict
import hashlib
import json
import math
import pickle
import shutil
import struct
import sys
import time
from pathlib import Path
from typing import BinaryIO, Iterable, Iterator, TextIO
from xml.sax.saxutils import quoteattr

import osmium

from source_identity import compute_source_identity
from world_common import ensure_pbf

CACHE_FORMAT = "BOSC1"
CACHE_DIR_NAME = "osm_source_cache"
SPOOL_FORMAT = "BOSC-SPOOL1"
SPOOL_DIR_NAME = "resume-spool"
SPOOL_MARKER_NAME = "complete.json"
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
FINALIZE_PROGRESS_INTERVAL = 100_000
NODE_BUCKETS = 64
MAX_OPEN_NODE_BUCKETS = 8
NODE_RECORD = struct.Struct("<qdd")

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


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while chunk := handle.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


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


def _node_record_iter(path: Path) -> Iterator[tuple[int, float, float]]:
    if not path.is_file():
        return
    with path.open("rb") as handle:
        while raw := handle.read(NODE_RECORD.size):
            if len(raw) != NODE_RECORD.size:
                raise ValueError(f"Corrupt compact node spool record: {path}")
            node_id, lon, lat = NODE_RECORD.unpack(raw)
            yield int(node_id), float(lon), float(lat)


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


class _ProgressDisplay:
    """Render one compact live view of source scan and route-match progress."""

    def __init__(
        self,
        source: Path,
        source_identity: dict[str, object],
        routes: Iterable[str],
        known_totals: dict[str, int],
        stream: TextIO | None = None,
    ) -> None:
        self.source = source
        self.digest = str(source_identity.get("digest", "unknown"))
        self.routes = tuple(sorted(routes))
        self.route_counts = {route: 0 for route in self.routes}
        self.total_items = sum(known_totals.values()) if len(known_totals) == 3 else None
        self.stream = stream if stream is not None else sys.stdout
        self.tty = bool(getattr(self.stream, "isatty", lambda: False)())
        self._rendered_lines = 0

    def hit(self, route: str) -> None:
        if route in self.route_counts:
            self.route_counts[route] += 1

    def _scan_text(self, scanned: int) -> str:
        if isinstance(self.total_items, int) and self.total_items >= scanned and self.total_items > 0:
            return f"{scanned:,} / {self.total_items:,} items"
        return f"{scanned:,} items"

    def render(self, counts: dict[str, int], elapsed: float) -> None:
        scanned = sum(counts.values())
        rate = scanned / max(0.001, elapsed)
        scan_text = self._scan_text(scanned)
        if not self.tty:
            routes = ", ".join(f"{route}={self.route_counts[route]:,}" for route in self.routes)
            print(
                f"[osm-source] scanned: {scan_text} | {rate:,.0f}/s | routes: {routes}",
                file=self.stream,
                flush=True,
            )
            return

        lines = [
            "[osm-source] single-pass ingest",
            f"source: {self.source.name}",
            f"sha256: {self.digest}",
            f"scanned: {scan_text} | {rate:,.0f}/s",
            "",
            "routes (matched source items):",
        ]
        lines.extend(f"  {route:<16} {self.route_counts[route]:>12,}" for route in self.routes)
        if self._rendered_lines:
            self.stream.write(f"\x1b[{self._rendered_lines}A")
        for line in lines:
            self.stream.write(f"\x1b[2K{line}\n")
        self.stream.flush()
        self._rendered_lines = len(lines)


class _FinalizeProgressDisplay:
    """Render compact live progress while the verified spool is finalized into route caches."""

    def __init__(
        self,
        routes: Iterable[str],
        stream: TextIO | None = None,
        interval: int = FINALIZE_PROGRESS_INTERVAL,
    ) -> None:
        self.routes = tuple(sorted(routes))
        self.route_counts = {route: 0 for route in self.routes}
        self.processed_records = 0
        self.phase = "selecting spool records"
        self.stream = stream if stream is not None else sys.stdout
        self.tty = bool(getattr(self.stream, "isatty", lambda: False)())
        self.interval = max(1, int(interval))
        self.started = time.perf_counter()
        self._last_rendered_records = -self.interval
        self._rendered_lines = 0

    def select(self, route: str, count: int = 1) -> None:
        if route in self.route_counts:
            self.route_counts[route] += count

    def record(self, count: int = 1) -> None:
        self.processed_records += count
        self.render()

    def set_phase(self, phase: str) -> None:
        self.phase = phase
        self.render(force=True)

    def render(self, force: bool = False) -> None:
        if not force and self.processed_records - self._last_rendered_records < self.interval:
            return
        elapsed = max(0.001, time.perf_counter() - self.started)
        rate = self.processed_records / elapsed
        routes = ", ".join(f"{route}={self.route_counts[route]:,}" for route in self.routes)
        if not self.tty:
            print(
                f"[osm-source] finalizing: {self.phase} | spool records: {self.processed_records:,} | "
                f"{rate:,.0f}/s | routes: {routes}",
                file=self.stream,
                flush=True,
            )
            self._last_rendered_records = self.processed_records
            return

        lines = [
            "[osm-source] route-cache finalization",
            f"phase: {self.phase}",
            f"spool records: {self.processed_records:,} | {rate:,.0f}/s",
            "",
            "routes (selected records):",
        ]
        lines.extend(f"  {route:<16} {self.route_counts[route]:>12,}" for route in self.routes)
        if self._rendered_lines:
            self.stream.write(f"\x1b[{self._rendered_lines}A")
        for line in lines:
            self.stream.write(f"\x1b[2K{line}\n")
        self.stream.flush()
        self._rendered_lines = len(lines)
        self._last_rendered_records = self.processed_records


class SourceCacheHandler(osmium.SimpleHandler):
    """Scan one OSM source and spool only facts needed to finalize stale routes."""

    def __init__(
        self,
        work_dir: Path,
        stale_routes: set[str],
        known_totals: dict[str, int],
        progress: _ProgressDisplay | None = None,
    ) -> None:
        super().__init__()
        self.work_dir = work_dir
        self.stale_routes = stale_routes
        self.known_totals = known_totals
        self.progress = progress
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

    def _hit(self, route: str) -> None:
        if self.progress is not None:
            self.progress.hit(route)

    def close(self) -> None:
        for handle in self._handles.values():
            handle.close()
        self._handles.clear()

    def _print_progress(self, kind: str, interval: int) -> None:
        current = self.counts[kind]
        if current == 0 or current % interval != 0:
            return
        elapsed = max(0.001, time.perf_counter() - self.started)
        if self.progress is not None:
            self.progress.render(self.counts, elapsed)
            return
        print(
            f"[osm-source] {kind}: {_progress_count(current, self.known_totals.get(kind))} | "
            f"{current / elapsed:,.0f}/s",
            flush=True,
        )

    def node(self, node: osmium.osm.Node) -> None:
        self.counts["nodes"] += 1
        if node.location.valid():
            tags = _tags_dict(node.tags)
            record = (int(node.id), float(node.lon), float(node.lat), tags)
            if "traffic_signals" in self.stale_routes and tags.get("highway") == "traffic_signals":
                self.signal_ids.add(int(node.id))
                _pickle_append(self._handle("traffic_signal_nodes"), record)
                self._hit("traffic_signals")
            if "pois" in self.stale_routes and _is_poi(tags):
                _pickle_append(self._handle("poi_nodes"), record)
                self._hit("pois")
            if "addresses" in self.stale_routes and _is_address(tags):
                _pickle_append(self._handle("address_nodes"), record)
                self._hit("addresses")
        self._print_progress("nodes", NODE_PROGRESS_INTERVAL)

    def way(self, way: osmium.osm.Way) -> None:
        self.counts["ways"] += 1
        tags = _tags_dict(way.tags)
        is_highway = bool(tags.get("highway"))
        is_signal_way = is_highway and any(int(ref.ref) in self.signal_ids for ref in way.nodes)
        is_poi = _is_poi(tags)
        is_address = _is_address(tags)
        is_area = _is_area_candidate(tags)

        selected = False
        if "highways" in self.stale_routes and is_highway:
            self._hit("highways")
            selected = True
        if "traffic_signals" in self.stale_routes and is_signal_way:
            self._hit("traffic_signals")
            selected = True
        if "pois" in self.stale_routes and is_poi:
            self._hit("pois")
            selected = True
        if "addresses" in self.stale_routes and is_address:
            self._hit("addresses")
            selected = True
        if "areas" in self.stale_routes:
            if is_area:
                self._hit("areas")
            selected = True

        if selected:
            _pickle_append(self._handle("ways"), _way_record(way, tags))
        self._print_progress("ways", WAY_PROGRESS_INTERVAL)

    def relation(self, relation: osmium.osm.Relation) -> None:
        self.counts["relations"] += 1
        if "areas" in self.stale_routes:
            tags = _tags_dict(relation.tags)
            relation_type = tags.get("type")
            if relation_type in {"multipolygon", "boundary"} or _is_area_candidate(tags):
                record = _relation_record(relation, tags)
                _pickle_append(self._handle("area_relations"), record)
                self._hit("areas")
                for member_type, member_ref, _role in record[1]:
                    if member_type == "w":
                        self.area_relation_way_ids.add(member_ref)
        self._print_progress("relations", RELATION_PROGRESS_INTERVAL)


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
        self.bucket_handles: OrderedDict[int, BinaryIO] = OrderedDict()
        self.tagged_bucket_handles: OrderedDict[int, BinaryIO] = OrderedDict()
        self.counts = {"nodes": 0, "ways": 0, "relations": 0}

    def _open_bucket(self, handles: OrderedDict[int, BinaryIO], bucket: int, suffix: str) -> BinaryIO:
        handle = handles.get(bucket)
        if handle is not None:
            handles.move_to_end(bucket)
            return handle
        if len(handles) >= MAX_OPEN_NODE_BUCKETS:
            _old_bucket, old_handle = handles.popitem(last=False)
            old_handle.close()
        handle = (self.work_dir / f"nodes-{bucket:02d}{suffix}").open("ab")
        handles[bucket] = handle
        return handle

    def _bucket(self, node_id: int) -> BinaryIO:
        bucket = node_id % NODE_BUCKETS
        return self._open_bucket(self.bucket_handles, bucket, ".bin")

    def _tagged_bucket(self, node_id: int) -> BinaryIO:
        bucket = node_id % NODE_BUCKETS
        return self._open_bucket(self.tagged_bucket_handles, bucket, ".tags.pkl")

    def add_node(self, node_id: int, lon: float, lat: float, tags: dict[str, str] | None = None) -> None:
        if not math.isfinite(lon) or not math.isfinite(lat):
            return
        node_tags = tags or {}
        if node_tags:
            _pickle_append(self._tagged_bucket(node_id), (node_id, lon, lat, node_tags))
        else:
            self._bucket(node_id).write(NODE_RECORD.pack(node_id, lon, lat))

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
        if not self.ways_file.closed:
            self.ways_file.close()
        if not self.relations_file.closed:
            self.relations_file.close()
        for handles in (self.bucket_handles, self.tagged_bucket_handles):
            for handle in handles.values():
                handle.close()
            handles.clear()

    def publish(self) -> dict[str, int]:
        self.close_inputs()
        temp = self.destination.with_suffix(self.destination.suffix + ".tmp")
        with temp.open("w", encoding="utf-8") as output:
            output.write('<?xml version="1.0" encoding="UTF-8"?>\n')
            output.write('<osm version="0.6" generator="brur-world-osm-source-cache">\n')
            for bucket in range(NODE_BUCKETS):
                compact_path = self.work_dir / f"nodes-{bucket:02d}.bin"
                tagged_path = self.work_dir / f"nodes-{bucket:02d}.tags.pkl"
                if not compact_path.is_file() and not tagged_path.is_file():
                    continue
                unique: dict[int, tuple[float, float, dict[str, str]]] = {}
                for node_id, lon, lat in _node_record_iter(compact_path):
                    if node_id not in unique:
                        unique[node_id] = (lon, lat, {})
                for raw in _pickle_iter(tagged_path):
                    node_id, lon, lat, tags = raw
                    unique[int(node_id)] = (float(lon), float(lat), dict(tags))
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


def _load_standalone_nodes(path: Path, writer: _RouteWriter, progress: _FinalizeProgressDisplay | None = None) -> None:
    for raw in _pickle_iter(path):
        node_id, lon, lat, tags = raw
        writer.add_node(int(node_id), float(lon), float(lat), dict(tags))
        if progress is not None:
            progress.select(writer.route)
            progress.record()


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


def _spool_routes(stale: set[str]) -> dict[str, int]:
    return {route: ROUTE_VERSIONS[route] for route in sorted(stale)}


def _spool_files(work_dir: Path) -> dict[str, dict[str, object]]:
    result: dict[str, dict[str, object]] = {}
    for path in sorted(work_dir.glob("*.pkl")):
        result[path.name] = {"size": path.stat().st_size, "sha256": _sha256(path)}
    return result


def _write_spool_marker(
    work_dir: Path,
    source_identity: dict[str, object],
    stale: set[str],
    counts: dict[str, int],
) -> None:
    _atomic_json(
        work_dir / SPOOL_MARKER_NAME,
        {
            "format": SPOOL_FORMAT,
            "source": source_identity,
            "routes": _spool_routes(stale),
            "source_scan": dict(counts),
            "files": _spool_files(work_dir),
        },
    )


def _load_completed_spool(
    work_dir: Path,
    source_identity: dict[str, object],
    stale: set[str],
) -> dict[str, int] | None:
    marker = _load_manifest(work_dir / SPOOL_MARKER_NAME)
    if marker.get("format") != SPOOL_FORMAT:
        return None
    if marker.get("source") != source_identity or marker.get("routes") != _spool_routes(stale):
        return None
    counts = marker.get("source_scan")
    if not isinstance(counts, dict):
        return None
    clean_counts: dict[str, int] = {}
    for key in ("nodes", "ways", "relations"):
        value = counts.get(key)
        if not isinstance(value, int) or value < 0:
            return None
        clean_counts[key] = value
    expected_files = marker.get("files")
    if not isinstance(expected_files, dict):
        return None
    actual_names = {path.name for path in work_dir.glob("*.pkl")}
    if actual_names != set(expected_files):
        return None
    for filename, expected in expected_files.items():
        if not isinstance(filename, str) or not isinstance(expected, dict):
            return None
        path = work_dir / filename
        size = expected.get("size")
        digest = expected.get("sha256")
        if not path.is_file() or not isinstance(size, int) or size < 0 or not isinstance(digest, str):
            return None
        if path.stat().st_size != size or _sha256(path) != digest:
            return None
    return clean_counts


def _spool_reference_sets(work_dir: Path, stale: set[str]) -> tuple[set[int], set[int]]:
    signal_ids: set[int] = set()
    if "traffic_signals" in stale:
        for raw in _pickle_iter(work_dir / "traffic_signal_nodes.pkl"):
            node_id, _lon, _lat, _tags = raw
            signal_ids.add(int(node_id))
    area_relation_way_ids: set[int] = set()
    if "areas" in stale:
        for raw in _pickle_iter(work_dir / "area_relations.pkl"):
            _relation_id, members, _tags = raw
            for member_type, member_ref, _role in members:
                if member_type == "w":
                    area_relation_way_ids.add(int(member_ref))
    return signal_ids, area_relation_way_ids


def _reset_route_work(work_dir: Path, stale: set[str]) -> None:
    for route in stale:
        route_dir = work_dir / f"route-{route}"
        if route_dir.exists():
            shutil.rmtree(route_dir)


def _finalize_spool(
    work_dir: Path,
    cache_dir: Path,
    stale: set[str],
    progress_stream: TextIO | None = None,
) -> dict[str, dict[str, int]]:
    _reset_route_work(work_dir, stale)
    signal_ids, area_relation_way_ids = _spool_reference_sets(work_dir, stale)
    writers = {
        route: _RouteWriter(route, work_dir, cache_dir / f"{route}.osm")
        for route in stale
    }
    progress = _FinalizeProgressDisplay(stale, stream=progress_stream)
    progress.render(force=True)
    try:
        if "traffic_signals" in writers:
            _load_standalone_nodes(work_dir / "traffic_signal_nodes.pkl", writers["traffic_signals"], progress)
        if "pois" in writers:
            _load_standalone_nodes(work_dir / "poi_nodes.pkl", writers["pois"], progress)
        if "addresses" in writers:
            _load_standalone_nodes(work_dir / "address_nodes.pkl", writers["addresses"], progress)

        ways_path = work_dir / "ways.pkl"
        if ways_path.is_file():
            for record in _pickle_iter(ways_path):
                for route, writer in writers.items():
                    if _select_way(route, record, signal_ids, area_relation_way_ids):
                        writer.add_way(record)
                        progress.select(route)
                progress.record()

        if "areas" in writers:
            for raw in _pickle_iter(work_dir / "area_relations.pkl"):
                writers["areas"].add_relation(raw)
                progress.select("areas")
                progress.record()

        route_counts: dict[str, dict[str, int]] = {}
        for route in sorted(writers):
            progress.set_phase(f"publishing {route}")
            route_counts[route] = writers[route].publish()
        progress.set_phase("complete")
        return route_counts
    finally:
        for writer in writers.values():
            writer.close_inputs()


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
    progress = _ProgressDisplay(source, source_identity, stale, known_totals)
    started = time.perf_counter()
    work_dir = cache_dir / SPOOL_DIR_NAME
    scan_counts = _load_completed_spool(work_dir, source_identity, stale)
    if scan_counts is None:
        if work_dir.exists():
            shutil.rmtree(work_dir)
        work_dir.mkdir(parents=True, exist_ok=True)
        handler = SourceCacheHandler(work_dir, stale, known_totals, progress)
        progress.render(handler.counts, 0.001)
        try:
            handler.apply_file(str(source), locations=True)
        finally:
            handler.close()
        scan_counts = dict(handler.counts)
        progress.render(scan_counts, max(0.001, time.perf_counter() - handler.started))
        _write_spool_marker(work_dir, source_identity, stale, scan_counts)
        print(f"[osm-source] source scan complete; resumable spool: {work_dir}", flush=True)
    else:
        print(f"[osm-source] resume verified spool without source rescan: {work_dir}", flush=True)

    route_counts = _finalize_spool(work_dir, cache_dir, stale)

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
        "source_scan": scan_counts,
        "routes": route_manifest,
    }
    _atomic_json(manifest_path, new_manifest)
    shutil.rmtree(work_dir)

    elapsed = time.perf_counter() - started
    print(
        f"[osm-source] complete in {elapsed:.1f}s | nodes={scan_counts['nodes']:,} "
        f"ways={scan_counts['ways']:,} relations={scan_counts['relations']:,}",
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
