#!/usr/bin/env python3
"""Build reusable OSM route caches without a full-Sweden Python spool.

Fast routes are written directly to route-local staging during one pyosmium
source traversal. Assembled areas use libosmium's area engine and a separate
streamed BAF1 cache so they never force every Sweden way through Python pickle.
"""

from __future__ import annotations

import argparse
from collections import OrderedDict
import json
import math
import os
import shutil
import struct
import sys
import time
from pathlib import Path
from typing import BinaryIO, Iterable, Iterator, TextIO
from xml.sax.saxutils import quoteattr

import osmium

from area_source_cache import area_source_cache_valid, build_area_source_cache
from source_identity import compute_source_identity
from world_common import ensure_pbf

CACHE_FORMAT = "BOSC2"
CACHE_DIR_NAME = "osm_source_cache"
# Retained as compatibility constants for older callers/tests. BOSC2 does not
# create or reuse a generic resume spool.
SPOOL_DIR_NAME = "resume-spool"
SPOOL_MARKER_NAME = "complete.json"
ROUTE_VERSIONS = {
    "highways": 2,
    "traffic_signals": 2,
    "pois": 2,
    "addresses": 2,
    "areas": 2,
}
ALL_ROUTES = tuple(ROUTE_VERSIONS)
NODE_PROGRESS_INTERVAL = 5_000_000
WAY_PROGRESS_INTERVAL = 250_000
RELATION_PROGRESS_INTERVAL = 50_000
NODE_BUCKETS = 64
MAX_OPEN_NODE_BUCKETS = 8
NODE_RECORD = struct.Struct("<qdd")

POI_KEYS = {
    "amenity", "shop", "tourism", "leisure", "office", "healthcare", "emergency",
    "public_transport", "railway", "aeroway", "craft", "historic", "sport", "club",
    "man_made", "information", "advertising",
}
SPECIAL_HIGHWAY_POIS = {"speed_camera", "services", "rest_area", "bus_stop", "elevator"}


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


def _source_matches(manifest: dict, source_identity: dict[str, object]) -> bool:
    source = manifest.get("source")
    return isinstance(source, dict) and source == source_identity


def _route_filename(route: str) -> str:
    return "areas.baf" if route == "areas" else f"{route}.osm"


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
    if filename != _route_filename(route):
        return False
    path = cache_dir / filename
    if route == "areas":
        return area_source_cache_valid(path)
    if not path.is_file() or path.stat().st_size < 32:
        return False
    try:
        with path.open("rb") as handle:
            handle.seek(max(0, path.stat().st_size - 128))
            return b"</osm>" in handle.read()
    except OSError:
        return False


def _load_manifest(path: Path) -> dict:
    if not path.is_file():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def _atomic_json(path: Path, value: dict) -> None:
    temp = path.with_suffix(path.suffix + f".tmp-{os.getpid()}")
    temp.write_text(json.dumps(value, indent=2, sort_keys=True), encoding="utf-8")
    temp.replace(path)


def _node_record_iter(path: Path) -> Iterator[tuple[int, float, float]]:
    if not path.is_file():
        return
    with path.open("rb") as handle:
        while raw := handle.read(NODE_RECORD.size):
            if len(raw) != NODE_RECORD.size:
                raise ValueError(f"Corrupt compact node staging record: {path}")
            node_id, lon, lat = NODE_RECORD.unpack(raw)
            yield int(node_id), float(lon), float(lat)


def _tagged_node_iter(path: Path) -> Iterator[tuple[int, float, float, dict[str, str]]]:
    if not path.is_file():
        return
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, 1):
            if not line.strip():
                continue
            try:
                value = json.loads(line)
                node_id, lon, lat, tags = value
            except (json.JSONDecodeError, TypeError, ValueError) as exc:
                raise ValueError(f"Corrupt tagged-node staging record {path}:{line_number}") from exc
            if not isinstance(tags, dict):
                raise ValueError(f"Corrupt tagged-node tags {path}:{line_number}")
            yield int(node_id), float(lon), float(lat), {str(k): str(v) for k, v in tags.items()}


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

    def hit(self, route: str, count: int = 1) -> None:
        if route in self.route_counts:
            self.route_counts[route] += count

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
            "[osm-source] direct route fan-out",
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


class _RouteWriter:
    """Stage one selected route directly and atomically publish OSM XML."""

    def __init__(self, route: str, work_dir: Path, destination: Path) -> None:
        self.route = route
        self.work_dir = work_dir / f"route-{route}"
        self.work_dir.mkdir(parents=True, exist_ok=True)
        self.destination = destination
        self.ways_path = self.work_dir / "ways.xml"
        self.ways_file: TextIO = self.ways_path.open("w", encoding="utf-8")
        self.bucket_handles: OrderedDict[int, BinaryIO] = OrderedDict()
        self.tagged_bucket_handles: OrderedDict[int, TextIO] = OrderedDict()
        self.counts = {"nodes": 0, "ways": 0, "relations": 0}

    def _open_binary_bucket(self, bucket: int) -> BinaryIO:
        handle = self.bucket_handles.get(bucket)
        if handle is not None:
            self.bucket_handles.move_to_end(bucket)
            return handle
        if len(self.bucket_handles) >= MAX_OPEN_NODE_BUCKETS:
            _, old = self.bucket_handles.popitem(last=False)
            old.close()
        handle = (self.work_dir / f"nodes-{bucket:02d}.bin").open("ab")
        self.bucket_handles[bucket] = handle
        return handle

    def _open_tagged_bucket(self, bucket: int) -> TextIO:
        handle = self.tagged_bucket_handles.get(bucket)
        if handle is not None:
            self.tagged_bucket_handles.move_to_end(bucket)
            return handle
        if len(self.tagged_bucket_handles) >= MAX_OPEN_NODE_BUCKETS:
            _, old = self.tagged_bucket_handles.popitem(last=False)
            old.close()
        handle = (self.work_dir / f"nodes-{bucket:02d}.tags.jsonl").open("a", encoding="utf-8")
        self.tagged_bucket_handles[bucket] = handle
        return handle

    def add_node(self, node_id: int, lon: float, lat: float, tags: dict[str, str] | None = None) -> None:
        if not math.isfinite(lon) or not math.isfinite(lat):
            return
        node_tags = tags or {}
        bucket = node_id % NODE_BUCKETS
        if node_tags:
            self._open_tagged_bucket(bucket).write(
                json.dumps([node_id, lon, lat, node_tags], ensure_ascii=False, separators=(",", ":")) + "\n"
            )
        else:
            self._open_binary_bucket(bucket).write(NODE_RECORD.pack(node_id, lon, lat))

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

    def close_inputs(self) -> None:
        if not self.ways_file.closed:
            self.ways_file.close()
        for handles in (self.bucket_handles, self.tagged_bucket_handles):
            for handle in handles.values():
                handle.close()
            handles.clear()

    def publish(self) -> dict[str, int]:
        self.close_inputs()
        temp = self.destination.with_suffix(self.destination.suffix + f".tmp-{os.getpid()}")
        with temp.open("w", encoding="utf-8") as output:
            output.write('<?xml version="1.0" encoding="UTF-8"?>\n')
            output.write('<osm version="0.6" generator="brur-world-osm-source-cache">\n')
            for bucket in range(NODE_BUCKETS):
                compact_path = self.work_dir / f"nodes-{bucket:02d}.bin"
                tagged_path = self.work_dir / f"nodes-{bucket:02d}.tags.jsonl"
                if not compact_path.is_file() and not tagged_path.is_file():
                    continue
                unique: dict[int, tuple[float, float, dict[str, str]]] = {}
                for node_id, lon, lat in _node_record_iter(compact_path):
                    if node_id not in unique:
                        unique[node_id] = (lon, lat, {})
                for node_id, lon, lat, tags in _tagged_node_iter(tagged_path):
                    unique[node_id] = (lon, lat, tags)
                for node_id in sorted(unique):
                    lon, lat, tags = unique[node_id]
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
            with self.ways_path.open("r", encoding="utf-8") as ways:
                shutil.copyfileobj(ways, output)
            output.write("</osm>\n")
        temp.replace(self.destination)
        return dict(self.counts)


class SourceCacheHandler(osmium.SimpleHandler):
    """Single-pass direct fan-out for non-area route caches."""

    def __init__(
        self,
        work_dir: Path,
        stale_routes: set[str],
        known_totals: dict[str, int],
        progress: _ProgressDisplay | None = None,
        writers: dict[str, _RouteWriter] | None = None,
    ) -> None:
        super().__init__()
        self.work_dir = work_dir
        self.stale_routes = set(stale_routes) - {"areas"}
        self.known_totals = known_totals
        self.progress = progress
        self.counts = {"nodes": 0, "ways": 0, "relations": 0}
        self.started = time.perf_counter()
        self.signal_ids: set[int] = set()
        self.writers = writers or {}

    def close(self) -> None:
        for writer in self.writers.values():
            writer.close_inputs()

    def _hit(self, route: str) -> None:
        if self.progress is not None:
            self.progress.hit(route)

    def _print_progress(self, kind: str, interval: int) -> None:
        current = self.counts[kind]
        if current == 0 or current % interval != 0:
            return
        elapsed = max(0.001, time.perf_counter() - self.started)
        if self.progress is not None:
            self.progress.render(self.counts, elapsed)
        else:
            print(
                f"[osm-source] {kind}: {_progress_count(current, self.known_totals.get(kind))} | "
                f"{current / elapsed:,.0f}/s",
                flush=True,
            )

    def node(self, node: osmium.osm.Node) -> None:
        self.counts["nodes"] += 1
        if node.location.valid():
            tags = _tags_dict(node.tags)
            node_id = int(node.id)
            lon, lat = float(node.lon), float(node.lat)
            if "traffic_signals" in self.stale_routes and tags.get("highway") == "traffic_signals":
                self.signal_ids.add(node_id)
                self.writers["traffic_signals"].add_node(node_id, lon, lat, tags)
                self._hit("traffic_signals")
            if "pois" in self.stale_routes and _is_poi(tags):
                self.writers["pois"].add_node(node_id, lon, lat, tags)
                self._hit("pois")
            if "addresses" in self.stale_routes and _is_address(tags):
                self.writers["addresses"].add_node(node_id, lon, lat, tags)
                self._hit("addresses")
        self._print_progress("nodes", NODE_PROGRESS_INTERVAL)

    def way(self, way: osmium.osm.Way) -> None:
        self.counts["ways"] += 1
        tags = _tags_dict(way.tags)
        is_highway = bool(tags.get("highway"))
        is_signal_way = is_highway and any(int(ref.ref) in self.signal_ids for ref in way.nodes)
        is_poi = _is_poi(tags)
        is_address = _is_address(tags)
        selected: list[str] = []
        if "highways" in self.stale_routes and is_highway:
            selected.append("highways")
        if "traffic_signals" in self.stale_routes and is_signal_way:
            selected.append("traffic_signals")
        if "pois" in self.stale_routes and is_poi:
            selected.append("pois")
        if "addresses" in self.stale_routes and is_address:
            selected.append("addresses")
        if selected:
            record = _way_record(way, tags)
            for route in selected:
                self.writers[route].add_way(record)
                self._hit(route)
        self._print_progress("ways", WAY_PROGRESS_INTERVAL)

    def relation(self, relation: osmium.osm.Relation) -> None:
        self.counts["relations"] += 1
        self._print_progress("relations", RELATION_PROGRESS_INTERVAL)


def _write_tags(output: TextIO, tags: dict[str, str], indent: str) -> None:
    for key in sorted(tags):
        output.write(f"{indent}<tag k={quoteattr(str(key))} v={quoteattr(str(tags[key]))}/>\n")


def build_source_caches(source: Path, cache_dir: Path, routes: Iterable[str] = ALL_ROUTES) -> dict[str, Path]:
    ensure_pbf(source)
    requested = tuple(dict.fromkeys(routes))
    unknown = [route for route in requested if route not in ROUTE_VERSIONS]
    if unknown:
        raise ValueError(f"Unknown OSM source cache route(s): {', '.join(unknown)}")
    cache_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = cache_dir / "manifest.json"

    identity_started = time.monotonic()
    source_identity = compute_source_identity(source, cache_dir / "source_identity.json")
    identity_elapsed = time.monotonic() - identity_started
    manifest = _load_manifest(manifest_path)
    same_source = _source_matches(manifest, source_identity)
    stale = {
        route for route in requested
        if not same_source or not _route_cache_valid(cache_dir, manifest, route)
    }
    outputs = {route: cache_dir / _route_filename(route) for route in requested}

    if not stale:
        print(
            f"[osm-source] CACHE HIT routes={','.join(requested)} identity={identity_elapsed:.3f}s "
            f"sha256={str(source_identity['digest'])[:12]}...",
            flush=True,
        )
        return outputs

    for route in requested:
        status = "REBUILD" if route in stale else "CACHE HIT"
        reason = "source/format/missing" if route in stale else "compatible"
        print(f"[plan] {route:<16} {status:<9} reason={reason}", flush=True)

    work_dir = cache_dir / f".direct-build-{os.getpid()}-{time.time_ns()}"
    fast_stale = set(stale) - {"areas"}
    scan_counts: dict[str, int] | None = None
    route_entries = dict(manifest.get("routes", {})) if same_source and isinstance(manifest.get("routes"), dict) else {}
    try:
        if fast_stale:
            work_dir.mkdir(parents=True, exist_ok=False)
            writers = {
                route: _RouteWriter(route, work_dir, cache_dir / _route_filename(route))
                for route in sorted(fast_stale)
            }
            progress = _ProgressDisplay(source, source_identity, fast_stale, {})
            handler = SourceCacheHandler(work_dir, fast_stale, {}, progress, writers)
            print(f"[osm-source] START direct routes={','.join(sorted(fast_stale))}", flush=True)
            started = time.monotonic()
            try:
                handler.apply_file(str(source), locations=True)
                elapsed_scan = time.monotonic() - started
                progress.render(handler.counts, max(0.001, elapsed_scan))
                scan_counts = dict(handler.counts)
                for route in sorted(fast_stale):
                    publish_started = time.monotonic()
                    counts = writers[route].publish()
                    route_entries[route] = {
                        "version": ROUTE_VERSIONS[route],
                        "complete": True,
                        "file": _route_filename(route),
                        "counts": counts,
                        "size_bytes": (cache_dir / _route_filename(route)).stat().st_size,
                    }
                    print(
                        f"[osm-source] DONE route={route} ways={counts['ways']:,} nodes={counts['nodes']:,} "
                        f"bytes={route_entries[route]['size_bytes']:,} elapsed={time.monotonic() - publish_started:.1f}s",
                        flush=True,
                    )
            finally:
                handler.close()

        if "areas" in stale:
            report = build_area_source_cache(source, cache_dir / _route_filename("areas"))
            route_entries["areas"] = {
                "version": ROUTE_VERSIONS["areas"],
                "complete": True,
                "file": _route_filename("areas"),
                "records": int(report["records"]),
                "size_bytes": int(report["bytes"]),
            }

        new_manifest = {
            "format": CACHE_FORMAT,
            "source": source_identity,
            "routes": route_entries,
        }
        if scan_counts is not None:
            new_manifest["source_scan"] = scan_counts
        elif same_source and isinstance(manifest.get("source_scan"), dict):
            new_manifest["source_scan"] = manifest["source_scan"]
        _atomic_json(manifest_path, new_manifest)
    finally:
        if work_dir.exists():
            shutil.rmtree(work_dir, ignore_errors=True)

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
