#!/usr/bin/env python3
"""Build/read compact streamed assembled-area source facts.

libosmium resolves provider relation/multipolygon structure once. The cache then
stores only normalized finished geometry, selected source tags and coastline
facts. Coordinates are centimetre-quantized projected metres: deterministic,
portable and much smaller/faster than JSON geometry or generated OSM-PBF.
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

MAGIC = b"BAF2"
VERSION = 1
HEADER = struct.Struct("<4sI")
FRAME = struct.Struct("<I")
FOOTER_MAGIC = b"BAFE"
FOOTER = struct.Struct("<4sQQ32s")
RECORD_COASTLINE = 1
RECORD_AREA_WAY = 2
RECORD_AREA_RELATION = 3
COAST_HEADER = struct.Struct("<BqI")
AREA_HEADER = struct.Struct("<BqqII")  # type, osm_id, area_id, tag_bytes, polygons
RING_HEADER = struct.Struct("<I")
HOLE_HEADER = struct.Struct("<I")
POINT = struct.Struct("<ii")
MAX_FRAME_BYTES = 256 * 1024 * 1024
MAX_TAG_BYTES = 4 * 1024 * 1024
PROGRESS_INTERVAL_S = 10.0
COORD_SCALE = 100.0

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


def _q(value: float) -> int:
    encoded = int(round(float(value) * COORD_SCALE))
    if encoded < -2_147_483_648 or encoded > 2_147_483_647:
        raise ValueError(f"projected coordinate outside BAF2 int32 range: {value}")
    return encoded


def _dq(value: int) -> float:
    return float(value) / COORD_SCALE


def _ring_points(ring: osmium.osm.NodeRefList) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    for node in ring:
        if not node.location.valid():
            continue
        points.append(project(node.lon, node.lat))
    if len(points) > 1 and points[0] == points[-1]:
        points.pop()
    return points


def _way_points(nodes: osmium.osm.WayNodeList) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    for node in nodes:
        if not node.location.valid():
            continue
        points.append(project(node.lon, node.lat))
    return points


def _encode_points(points: list[tuple[float, float]]) -> bytes:
    payload = bytearray(RING_HEADER.pack(len(points)))
    for x, y in points:
        payload.extend(POINT.pack(_q(x), _q(y)))
    return bytes(payload)


def _encode_coastline(osm_id: int, points: list[tuple[float, float]]) -> bytes:
    payload = bytearray(COAST_HEADER.pack(RECORD_COASTLINE, int(osm_id), len(points)))
    for x, y in points:
        payload.extend(POINT.pack(_q(x), _q(y)))
    return bytes(payload)


def _encode_area(osm_type: int, osm_id: int, area_id: int, tags: dict[str, str], polygons: list[dict]) -> bytes:
    tag_bytes = json.dumps(tags, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    if len(tag_bytes) > MAX_TAG_BYTES:
        raise ValueError(f"area tags too large for OSM {osm_id}: {len(tag_bytes)} bytes")
    payload = bytearray(AREA_HEADER.pack(osm_type, int(osm_id), int(area_id), len(tag_bytes), len(polygons)))
    payload.extend(tag_bytes)
    for polygon in polygons:
        outer = polygon["outer"]
        holes = polygon["holes"]
        payload.extend(_encode_points(outer))
        payload.extend(HOLE_HEADER.pack(len(holes)))
        for hole in holes:
            payload.extend(_encode_points(hole))
    return bytes(payload)


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

    def _write_payload(self, payload: bytes) -> None:
        if not payload or len(payload) > MAX_FRAME_BYTES:
            raise ValueError(f"invalid BAF2 frame size: {len(payload)}")
        framed = FRAME.pack(len(payload)) + payload
        self.handle.write(framed)
        self.digest.update(framed)
        self.bytes_written += len(framed)
        self.payload_bytes += len(framed)
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
        if way.tags.get("natural") != "coastline":
            return
        try:
            points = _way_points(way.nodes)
        except osmium.InvalidLocationError:
            return
        if len(points) < 2:
            return
        self.coastlines += 1
        self._write_payload(_encode_coastline(int(way.id), points))

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
        record_type = RECORD_AREA_WAY if area.from_way() else RECORD_AREA_RELATION
        self._write_payload(_encode_area(record_type, int(area.orig_id()), int(area.id), tags, polygons))


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
        "records": handler.records,
        "coastlines": handler.coastlines,
        "size_bytes": handler.bytes_written,
        "sha256": content_digest.hex(),
        "elapsed_s": elapsed,
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
    return {
        "records": records,
        "payload_bytes": payload_bytes,
        "size_bytes": path.stat().st_size,
        "sha256": digest.hex(),
    }


def _read_points(payload: memoryview, offset: int) -> tuple[list[list[float]], int]:
    if offset + RING_HEADER.size > len(payload):
        raise ValueError("truncated BAF2 ring header")
    (count,) = RING_HEADER.unpack_from(payload, offset)
    offset += RING_HEADER.size
    required = count * POINT.size
    if offset + required > len(payload):
        raise ValueError("truncated BAF2 ring points")
    points: list[list[float]] = []
    for _ in range(count):
        x, y = POINT.unpack_from(payload, offset)
        offset += POINT.size
        points.append([_dq(x), _dq(y)])
    return points, offset


def _decode_record(raw: bytes) -> dict:
    payload = memoryview(raw)
    if not payload:
        raise ValueError("empty BAF2 record")
    record_type = int(payload[0])
    if record_type == RECORD_COASTLINE:
        if len(payload) < COAST_HEADER.size:
            raise ValueError("truncated BAF2 coastline")
        _, osm_id, count = COAST_HEADER.unpack_from(payload, 0)
        offset = COAST_HEADER.size
        required = count * POINT.size
        if offset + required != len(payload):
            raise ValueError("invalid BAF2 coastline payload size")
        points: list[list[float]] = []
        for _ in range(count):
            x, y = POINT.unpack_from(payload, offset)
            offset += POINT.size
            points.append([_dq(x), _dq(y)])
        return {
            "osm_type": "way",
            "osm_id": int(osm_id),
            "geometry_type": "coastline",
            "tags": {"natural": "coastline"},
            "geometry": points,
        }

    if record_type not in {RECORD_AREA_WAY, RECORD_AREA_RELATION} or len(payload) < AREA_HEADER.size:
        raise ValueError(f"invalid BAF2 record type: {record_type}")
    _, osm_id, area_id, tag_size, polygon_count = AREA_HEADER.unpack_from(payload, 0)
    offset = AREA_HEADER.size
    if tag_size > MAX_TAG_BYTES or offset + tag_size > len(payload):
        raise ValueError("invalid BAF2 tag payload")
    tags = json.loads(bytes(payload[offset:offset + tag_size]))
    if not isinstance(tags, dict):
        raise ValueError("invalid BAF2 tags")
    offset += tag_size
    polygons: list[dict] = []
    for _ in range(polygon_count):
        outer, offset = _read_points(payload, offset)
        if offset + HOLE_HEADER.size > len(payload):
            raise ValueError("truncated BAF2 hole header")
        (hole_count,) = HOLE_HEADER.unpack_from(payload, offset)
        offset += HOLE_HEADER.size
        holes: list[list[list[float]]] = []
        for _ in range(hole_count):
            hole, offset = _read_points(payload, offset)
            holes.append(hole)
        polygons.append({"outer": outer, "holes": holes})
    if offset != len(payload):
        raise ValueError("BAF2 area payload trailing bytes")
    return {
        "osm_type": "way" if record_type == RECORD_AREA_WAY else "relation",
        "osm_id": int(osm_id),
        "area_id": int(area_id),
        "geometry_type": "area",
        "tags": {str(k): str(v) for k, v in tags.items()},
        "geometry": polygons,
    }


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
            if size <= 0 or size > MAX_FRAME_BYTES:
                raise ValueError(f"invalid area frame size {size}: {path}")
            payload = handle.read(size)
            if len(payload) != size or handle.tell() > payload_end:
                raise ValueError(f"truncated area frame payload: {path}")
            records += 1
            yield _decode_record(payload)
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
