#!/usr/bin/env python3
"""Build/read the streamed assembled-area/background source cache.

The cache stores only source facts used by current building/background
consumers. Polygon areas are assembled by libosmium; directed coastline ways
are retained separately so coastline, not an administrative polygon, owns the
land/ocean split. This is rebuild-only source data, not runtime world truth.
"""
from __future__ import annotations

import hashlib
import json
import os
import struct
import time
from pathlib import Path
from typing import BinaryIO, Iterator

import osmium

from world_common import ensure_pbf, project

MAGIC = b"BAF1"
VERSION = 3
HEADER = struct.Struct("<4sI")
FRAME = struct.Struct("<I")
FOOTER_MAGIC = b"BAFE"
FOOTER = struct.Struct("<4sQQ32s")
PROGRESS_INTERVAL_S = 10.0

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


def is_poi_tags(tags: dict[str, str]) -> bool:
    if any(key in tags for key in POI_KEYS):
        return True
    if tags.get("highway") in SPECIAL_HIGHWAY_POIS:
        return True
    if "enforcement" in tags or "surveillance" in tags:
        return True
    return any(key.startswith("camera:") for key in tags)


def is_area_candidate_tags(tags: dict[str, str]) -> bool:
    if tags.get("building") is not None or tags.get("building:part") is not None:
        return True
    if is_poi_tags(tags):
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


def _ring_points(ring: osmium.osm.NodeRefList) -> list[list[float]]:
    points: list[list[float]] = []
    for node in ring:
        if not node.location.valid():
            continue
        x, y = project(node.lon, node.lat)
        points.append([x, y])
    if len(points) > 1 and points[0] == points[-1]:
        points.pop()
    return points


def _way_points(nodes: osmium.osm.WayNodeList) -> list[list[float]]:
    points: list[list[float]] = []
    for node in nodes:
        if not node.location.valid():
            continue
        x, y = project(node.lon, node.lat)
        points.append([x, y])
    return points


def _write_frame(handle: BinaryIO, digest: "hashlib._Hash", value: dict) -> int:
    payload = json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")
    framed = FRAME.pack(len(payload)) + payload
    handle.write(framed)
    digest.update(framed)
    return len(framed)


class AreaFactHandler(osmium.SimpleHandler):
    def __init__(self, handle: BinaryIO, digest: "hashlib._Hash") -> None:
        super().__init__()
        self.handle = handle
        self.digest = digest
        self.records = 0
        self.coastlines = 0
        self.payload_bytes = 0
        self.bytes_written = HEADER.size
        self.started = time.monotonic()
        self.last_progress = self.started

    def _write(self, record: dict) -> None:
        frame_bytes = _write_frame(self.handle, self.digest, record)
        self.bytes_written += frame_bytes
        self.payload_bytes += frame_bytes
        self.records += 1
        now = time.monotonic()
        if now - self.last_progress >= PROGRESS_INTERVAL_S:
            elapsed = max(0.001, now - self.started)
            print(
                f"[area-facts] records={self.records:,} coastlines={self.coastlines:,} "
                f"bytes={self.bytes_written:,} rate={self.records / elapsed:,.0f}/s elapsed={elapsed:.1f}s",
                flush=True,
            )
            self.last_progress = now

    def way(self, way: osmium.osm.Way) -> None:
        tags = {str(tag.k): str(tag.v) for tag in way.tags}
        if tags.get("natural") != "coastline":
            return
        try:
            points = _way_points(way.nodes)
        except osmium.InvalidLocationError:
            return
        if len(points) < 2:
            return
        self.coastlines += 1
        self._write({
            "osm_type": "way", "osm_id": int(way.id), "geometry_type": "coastline",
            "tags": {"natural": "coastline"}, "geometry": points,
        })

    def area(self, area: osmium.osm.Area) -> None:
        tags = {str(tag.k): str(tag.v) for tag in area.tags}
        if not is_area_candidate_tags(tags):
            return
        polygons: list[dict[str, list]] = []
        for outer in area.outer_rings():
            try:
                shell = _ring_points(outer)
                holes = [_ring_points(inner) for inner in area.inner_rings(outer)]
            except osmium.InvalidLocationError:
                continue
            if len(shell) < 3:
                continue
            polygons.append({"outer": shell, "holes": [hole for hole in holes if len(hole) >= 3]})
        if not polygons:
            return
        self._write({
            "osm_type": "way" if area.from_way() else "relation",
            "osm_id": int(area.orig_id()), "area_id": int(area.id),
            "geometry_type": "area", "tags": tags, "geometry": polygons,
        })


def build_area_source_cache(source: Path, destination: Path) -> dict[str, int | float | str]:
    ensure_pbf(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temp = destination.with_suffix(destination.suffix + f".tmp-{os.getpid()}-{time.time_ns()}")
    started = time.monotonic()
    print(f"[area-facts] START source={source}", flush=True)
    try:
        with temp.open("wb") as handle:
            digest = hashlib.sha256()
            header = HEADER.pack(MAGIC, VERSION)
            handle.write(header)
            digest.update(header)
            handler = AreaFactHandler(handle, digest)
            handler.apply_file(str(source), locations=True)
            content_digest = digest.digest()
            handle.write(FOOTER.pack(FOOTER_MAGIC, handler.records, handler.payload_bytes, content_digest))
            handler.bytes_written += FOOTER.size
            handle.flush()
            os.fsync(handle.fileno())
        temp.replace(destination)
    except BaseException:
        try:
            temp.unlink()
        except OSError:
            pass
        raise
    elapsed = time.monotonic() - started
    print(
        f"[area-facts] DONE records={handler.records:,} coastlines={handler.coastlines:,} "
        f"bytes={handler.bytes_written:,} sha256={content_digest.hex()[:12]}... elapsed={elapsed:.1f}s",
        flush=True,
    )
    return {
        "records": handler.records, "coastlines": handler.coastlines,
        "size_bytes": handler.bytes_written, "sha256": content_digest.hex(), "elapsed_s": elapsed,
    }


def _footer(path: Path) -> tuple[int, int, bytes]:
    if path.stat().st_size < HEADER.size + FOOTER.size:
        raise ValueError(f"truncated area source cache: {path}")
    with path.open("rb") as handle:
        handle.seek(-FOOTER.size, os.SEEK_END)
        magic, records, payload_bytes, digest = FOOTER.unpack(handle.read(FOOTER.size))
    if magic != FOOTER_MAGIC:
        raise ValueError(f"missing area cache completion footer: {path}")
    expected = HEADER.size + int(payload_bytes) + FOOTER.size
    if path.stat().st_size != expected:
        raise ValueError(f"area cache size mismatch: expected={expected} actual={path.stat().st_size}")
    return int(records), int(payload_bytes), digest


def area_source_cache_metadata(path: Path) -> dict[str, int | str]:
    records, payload_bytes, digest = _footer(path)
    with path.open("rb") as handle:
        raw = handle.read(HEADER.size)
    magic, version = HEADER.unpack(raw)
    if magic != MAGIC or version != VERSION:
        raise ValueError(f"unsupported area source cache: magic={magic!r} version={version}")
    return {"records": records, "payload_bytes": payload_bytes, "size_bytes": path.stat().st_size, "sha256": digest.hex()}


def iter_area_facts(path: Path) -> Iterator[dict]:
    records_expected, payload_bytes, _ = _footer(path)
    with path.open("rb") as handle:
        raw_header = handle.read(HEADER.size)
        if len(raw_header) != HEADER.size:
            raise ValueError(f"truncated area source cache: {path}")
        magic, version = HEADER.unpack(raw_header)
        if magic != MAGIC or version != VERSION:
            raise ValueError(f"unsupported area source cache: magic={magic!r} version={version}")
        payload_end = HEADER.size + payload_bytes
        records = 0
        while handle.tell() < payload_end:
            raw_size = handle.read(FRAME.size)
            if len(raw_size) != FRAME.size:
                raise ValueError(f"truncated area frame header: {path}")
            (size,) = FRAME.unpack(raw_size)
            if size <= 0 or size > 256 * 1024 * 1024:
                raise ValueError(f"invalid area frame size {size}: {path}")
            payload = handle.read(size)
            if len(payload) != size or handle.tell() > payload_end:
                raise ValueError(f"truncated area frame payload: {path}")
            value = json.loads(payload)
            if not isinstance(value, dict) or not isinstance(value.get("geometry"), list):
                raise ValueError(f"invalid area record: {path}")
            records += 1
            yield value
        if records != records_expected:
            raise ValueError(f"area cache record count mismatch: expected={records_expected} actual={records}")


def area_source_cache_valid(path: Path) -> bool:
    if not path.is_file():
        return False
    try:
        area_source_cache_metadata(path)
        return True
    except (OSError, ValueError, struct.error):
        return False
