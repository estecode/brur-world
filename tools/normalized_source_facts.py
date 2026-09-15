"""Small streamed normalized-source cache format for offline world builders.

This is deliberately not an OSM container. Source adapters resolve provider
references/geometry first, then write normalized facts which downstream BRUR
builders can consume sequentially without reparsing PBF.
"""
from __future__ import annotations

import hashlib
import json
import os
import struct
import time
from pathlib import Path
from typing import BinaryIO, Iterator

MAGIC = b"BSF1"
VERSION = 1
HEADER = struct.Struct("<4sII")
FRAME = struct.Struct("<I")
FOOTER_MAGIC = b"BSFE"
FOOTER = struct.Struct("<4sQQ32s")
MAX_FRAME_BYTES = 256 * 1024 * 1024


class FactWriter:
    """Atomic framed writer with count/bytes/SHA computed while writing."""

    def __init__(self, destination: Path, schema: int) -> None:
        self.destination = Path(destination)
        self.destination.parent.mkdir(parents=True, exist_ok=True)
        self.temp = self.destination.with_suffix(self.destination.suffix + f".tmp-{os.getpid()}-{time.time_ns()}")
        self.handle: BinaryIO = self.temp.open("wb")
        self.digest = hashlib.sha256()
        self.records = 0
        self.payload_bytes = 0
        self.closed = False
        self._write(HEADER.pack(MAGIC, VERSION, int(schema)))

    def _write(self, data: bytes) -> None:
        self.handle.write(data)
        self.digest.update(data)

    def write(self, fact: dict) -> None:
        payload = json.dumps(fact, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
        if not payload or len(payload) > MAX_FRAME_BYTES:
            raise ValueError(f"invalid source-fact frame size: {len(payload)}")
        framed = FRAME.pack(len(payload)) + payload
        self._write(framed)
        self.records += 1
        self.payload_bytes += len(framed)

    def publish(self) -> dict[str, int | str]:
        if self.closed:
            raise RuntimeError("source-fact writer already closed")
        content_sha = self.digest.digest()
        # Footer is a completion marker. The digest covers header+frames and is
        # already known here; publication never rereads the completed file.
        self.handle.write(FOOTER.pack(FOOTER_MAGIC, self.records, self.payload_bytes, content_sha))
        self.handle.flush()
        os.fsync(self.handle.fileno())
        self.handle.close()
        self.closed = True
        self.temp.replace(self.destination)
        return {"records": self.records, "size_bytes": self.destination.stat().st_size, "sha256": content_sha.hex()}

    def abort(self) -> None:
        if not self.closed:
            self.handle.close()
            self.closed = True
        try:
            self.temp.unlink()
        except OSError:
            pass


def _read_metadata(path: Path) -> tuple[int, int, int, bytes]:
    size = path.stat().st_size
    if size < HEADER.size + FOOTER.size:
        raise ValueError(f"truncated source-fact cache: {path}")
    with path.open("rb") as handle:
        raw = handle.read(HEADER.size)
        magic, version, schema = HEADER.unpack(raw)
        if magic != MAGIC or version != VERSION:
            raise ValueError(f"unsupported source-fact cache: {path}")
        handle.seek(-FOOTER.size, os.SEEK_END)
        footer_magic, records, payload_bytes, digest = FOOTER.unpack(handle.read(FOOTER.size))
    if footer_magic != FOOTER_MAGIC:
        raise ValueError(f"incomplete source-fact cache: {path}")
    if size != HEADER.size + payload_bytes + FOOTER.size:
        raise ValueError(f"source-fact cache size mismatch: {path}")
    return schema, records, payload_bytes, digest


def validate(path: Path, schema: int | None = None) -> dict[str, int | str]:
    actual_schema, records, payload_bytes, digest = _read_metadata(path)
    if schema is not None and actual_schema != schema:
        raise ValueError(f"source-fact schema mismatch: expected={schema} actual={actual_schema}")
    return {"schema": actual_schema, "records": records, "payload_bytes": payload_bytes, "size_bytes": path.stat().st_size, "sha256": digest.hex()}


def iter_facts(path: Path, schema: int | None = None) -> Iterator[dict]:
    actual_schema, expected_records, payload_bytes, _ = _read_metadata(path)
    if schema is not None and actual_schema != schema:
        raise ValueError(f"source-fact schema mismatch: expected={schema} actual={actual_schema}")
    payload_end = HEADER.size + payload_bytes
    records = 0
    with path.open("rb") as handle:
        handle.seek(HEADER.size)
        while handle.tell() < payload_end:
            raw = handle.read(FRAME.size)
            if len(raw) != FRAME.size:
                raise ValueError(f"truncated source-fact frame: {path}")
            (size,) = FRAME.unpack(raw)
            if size <= 0 or size > MAX_FRAME_BYTES:
                raise ValueError(f"invalid source-fact frame size {size}: {path}")
            payload = handle.read(size)
            if len(payload) != size or handle.tell() > payload_end:
                raise ValueError(f"truncated source-fact payload: {path}")
            value = json.loads(payload)
            if not isinstance(value, dict):
                raise ValueError(f"invalid source-fact record: {path}")
            records += 1
            yield value
    if records != expected_records:
        raise ValueError(f"source-fact record count mismatch: expected={expected_records} actual={records}")
