"""Compact streamed normalized highway source facts for BRUR offline builders."""
from __future__ import annotations

import hashlib
import json
import os
import struct
import time
from pathlib import Path
from typing import BinaryIO, Iterator, Mapping, Sequence

from routing_graph import WayInput
from world_common import project

MAGIC = b"BHF1"
VERSION = 1
HEADER = struct.Struct("<4sI")
WAY_HEADER = struct.Struct("<qIH")  # way id, node count, tag-json bytes
NODE = struct.Struct("<qii")        # node id, lon_e7, lat_e7
FOOTER_MAGIC = b"BHFE"
FOOTER = struct.Struct("<4sQQ32s") # magic, records, payload bytes, sha256(header+payload)
MAX_TAG_BYTES = 65535


class HighwayFactWriter:
    """Atomic compact writer; checksum/count/bytes are accumulated while writing."""

    def __init__(self, destination: Path) -> None:
        self.destination = Path(destination)
        self.destination.parent.mkdir(parents=True, exist_ok=True)
        self.temp = self.destination.with_suffix(self.destination.suffix + f".tmp-{os.getpid()}-{time.time_ns()}")
        self.handle: BinaryIO = self.temp.open("wb")
        self.digest = hashlib.sha256()
        self.records = 0
        self.payload_bytes = 0
        self.closed = False
        header = HEADER.pack(MAGIC, VERSION)
        self.handle.write(header)
        self.digest.update(header)

    def _write(self, data: bytes) -> None:
        self.handle.write(data)
        self.digest.update(data)
        self.payload_bytes += len(data)

    def write_way(
        self,
        way_id: int,
        node_ids: Sequence[int],
        lonlat: Sequence[tuple[float, float]],
        tags: Mapping[str, str],
    ) -> None:
        if len(node_ids) != len(lonlat) or len(node_ids) < 2:
            raise ValueError(f"invalid highway fact way {way_id}: ids={len(node_ids)} coords={len(lonlat)}")
        tag_bytes = json.dumps(dict(tags), ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
        if len(tag_bytes) > MAX_TAG_BYTES:
            raise ValueError(f"highway tags too large for way {way_id}: {len(tag_bytes)} bytes")
        self._write(WAY_HEADER.pack(int(way_id), len(node_ids), len(tag_bytes)))
        self._write(tag_bytes)
        for node_id, (lon, lat) in zip(node_ids, lonlat):
            lon_e7 = int(round(float(lon) * 10_000_000.0))
            lat_e7 = int(round(float(lat) * 10_000_000.0))
            self._write(NODE.pack(int(node_id), lon_e7, lat_e7))
        self.records += 1

    def publish(self) -> dict[str, int | str]:
        if self.closed:
            raise RuntimeError("highway fact writer already closed")
        content_sha = self.digest.digest()
        self.handle.write(FOOTER.pack(FOOTER_MAGIC, self.records, self.payload_bytes, content_sha))
        self.handle.flush()
        os.fsync(self.handle.fileno())
        self.handle.close()
        self.closed = True
        self.temp.replace(self.destination)
        return {
            "records": self.records,
            "payload_bytes": self.payload_bytes,
            "size_bytes": self.destination.stat().st_size,
            "sha256": content_sha.hex(),
        }

    def abort(self) -> None:
        if not self.closed:
            self.handle.close()
            self.closed = True
        try:
            self.temp.unlink()
        except OSError:
            pass


def _metadata(path: Path) -> tuple[int, int, bytes]:
    size = path.stat().st_size
    if size < HEADER.size + FOOTER.size:
        raise ValueError(f"truncated highway fact cache: {path}")
    with path.open("rb") as handle:
        header = handle.read(HEADER.size)
        magic, version = HEADER.unpack(header)
        if magic != MAGIC or version != VERSION:
            raise ValueError(f"unsupported highway fact cache: {path}")
        handle.seek(-FOOTER.size, os.SEEK_END)
        footer_magic, records, payload_bytes, digest = FOOTER.unpack(handle.read(FOOTER.size))
    if footer_magic != FOOTER_MAGIC:
        raise ValueError(f"incomplete highway fact cache: {path}")
    if size != HEADER.size + payload_bytes + FOOTER.size:
        raise ValueError(f"highway fact cache size mismatch: {path}")
    return int(records), int(payload_bytes), digest


def validate_highways(path: Path) -> dict[str, int | str]:
    records, payload_bytes, digest = _metadata(path)
    return {
        "records": records,
        "payload_bytes": payload_bytes,
        "size_bytes": path.stat().st_size,
        "sha256": digest.hex(),
    }


def iter_highway_ways(path: Path) -> Iterator[WayInput]:
    expected_records, payload_bytes, _ = _metadata(path)
    payload_end = HEADER.size + payload_bytes
    records = 0
    with path.open("rb") as handle:
        handle.seek(HEADER.size)
        while handle.tell() < payload_end:
            raw = handle.read(WAY_HEADER.size)
            if len(raw) != WAY_HEADER.size:
                raise ValueError(f"truncated highway way header: {path}")
            way_id, node_count, tag_size = WAY_HEADER.unpack(raw)
            if node_count < 2 or tag_size > MAX_TAG_BYTES:
                raise ValueError(f"invalid highway fact record for way {way_id}")
            tag_bytes = handle.read(tag_size)
            if len(tag_bytes) != tag_size:
                raise ValueError(f"truncated highway tags for way {way_id}")
            tags = json.loads(tag_bytes)
            if not isinstance(tags, dict):
                raise ValueError(f"invalid highway tags for way {way_id}")
            node_ids: list[int] = []
            coordinates: list[tuple[float, float]] = []
            for _ in range(node_count):
                raw_node = handle.read(NODE.size)
                if len(raw_node) != NODE.size:
                    raise ValueError(f"truncated highway nodes for way {way_id}")
                node_id, lon_e7, lat_e7 = NODE.unpack(raw_node)
                node_ids.append(int(node_id))
                coordinates.append((lon_e7 / 10_000_000.0, lat_e7 / 10_000_000.0))
            if handle.tell() > payload_end:
                raise ValueError(f"highway fact payload overrun: {path}")
            records += 1
            yield WayInput(int(way_id), node_ids, coordinates, {str(k): str(v) for k, v in tags.items()})
    if records != expected_records:
        raise ValueError(f"highway fact record count mismatch: expected={expected_records} actual={records}")


def projected_points(way: WayInput) -> list[tuple[float, float]]:
    return [project(lon, lat) for lon, lat in way.coordinates]
