#!/usr/bin/env python3
"""Build/read a small streamed assembled-area source cache.

The cache stores only area facts used by current building/background consumers.
It is rebuild-only source data, not runtime world truth.
"""

from __future__ import annotations

import json
import os
import struct
import time
from pathlib import Path
from typing import BinaryIO, Iterator

import osmium

from world_common import ensure_pbf, project

MAGIC = b"BAF1"
VERSION = 1
HEADER = struct.Struct("<4sI")
FRAME = struct.Struct("<I")
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


def _write_frame(handle: BinaryIO, value: dict) -> int:
    payload = json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")
    handle.write(FRAME.pack(len(payload)))
    handle.write(payload)
    return FRAME.size + len(payload)


class AreaFactHandler(osmium.SimpleHandler):
    def __init__(self, handle: BinaryIO) -> None:
        super().__init__()
        self.handle = handle
        self.records = 0
        self.bytes_written = HEADER.size
        self.started = time.monotonic()
        self.last_progress = self.started

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
        record = {
            "osm_type": "way" if area.from_way() else "relation",
            "osm_id": int(area.orig_id()),
            "tags": tags,
            "geometry": polygons,
        }
        self.bytes_written += _write_frame(self.handle, record)
        self.records += 1
        now = time.monotonic()
        if now - self.last_progress >= PROGRESS_INTERVAL_S:
            elapsed = max(0.001, now - self.started)
            print(
                f"[area-facts] records={self.records:,} bytes={self.bytes_written:,} "
                f"rate={self.records / elapsed:,.0f}/s elapsed={elapsed:.1f}s",
                flush=True,
            )
            self.last_progress = now


def build_area_source_cache(source: Path, destination: Path) -> dict[str, int | float]:
    ensure_pbf(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temp = destination.with_suffix(destination.suffix + f".tmp-{os.getpid()}-{time.time_ns()}")
    started = time.monotonic()
    print(f"[area-facts] START source={source}", flush=True)
    try:
        with temp.open("wb") as handle:
            handle.write(HEADER.pack(MAGIC, VERSION))
            handler = AreaFactHandler(handle)
            handler.apply_file(str(source), locations=True)
            handle.flush()
            os.fsync(handle.fileno())
        temp.replace(destination)
    except Exception:
        try:
            temp.unlink()
        except OSError:
            pass
        raise
    elapsed = time.monotonic() - started
    print(
        f"[area-facts] DONE records={handler.records:,} bytes={handler.bytes_written:,} elapsed={elapsed:.1f}s",
        flush=True,
    )
    return {"records": handler.records, "bytes": handler.bytes_written, "elapsed_s": elapsed}


def iter_area_facts(path: Path) -> Iterator[dict]:
    with path.open("rb") as handle:
        raw_header = handle.read(HEADER.size)
        if len(raw_header) != HEADER.size:
            raise ValueError(f"truncated area source cache: {path}")
        magic, version = HEADER.unpack(raw_header)
        if magic != MAGIC or version != VERSION:
            raise ValueError(f"unsupported area source cache: magic={magic!r} version={version}")
        while True:
            raw_size = handle.read(FRAME.size)
            if not raw_size:
                break
            if len(raw_size) != FRAME.size:
                raise ValueError(f"truncated area frame header: {path}")
            (size,) = FRAME.unpack(raw_size)
            if size <= 0 or size > 256 * 1024 * 1024:
                raise ValueError(f"invalid area frame size {size}: {path}")
            payload = handle.read(size)
            if len(payload) != size:
                raise ValueError(f"truncated area frame payload: {path}")
            value = json.loads(payload)
            if not isinstance(value, dict) or not isinstance(value.get("geometry"), list):
                raise ValueError(f"invalid area record: {path}")
            yield value


def area_source_cache_valid(path: Path) -> bool:
    if not path.is_file() or path.stat().st_size <= HEADER.size:
        return False
    try:
        with path.open("rb") as handle:
            raw = handle.read(HEADER.size)
        return len(raw) == HEADER.size and HEADER.unpack(raw) == (MAGIC, VERSION)
    except (OSError, ValueError, struct.error):
        return False
