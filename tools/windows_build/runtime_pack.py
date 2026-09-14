#!/usr/bin/env python3
"""Builds and reuses a content-addressed Windows runtime world-data resource pack.

Dependencies:
- Uses prepare_runtime_data.py as the single Windows runtime-selection contract.
- Reads authoritative generated world_data without rebuilding it.
- Stores only local verification metadata/hashes and derived ZIP resource packs in a cache.
- Transcodes BMC2 building chunks to compact BMC3 only inside the derived Windows pack.
- Stores seek-heavy routing datasets uncompressed so runtime random access stays bounded.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import struct
import sys
import tempfile
import time
import zipfile
from collections import defaultdict
from pathlib import Path
from typing import Any

WINDOWS_BUILD_DIR = Path(__file__).resolve().parent
if str(WINDOWS_BUILD_DIR) not in sys.path:
    sys.path.insert(0, str(WINDOWS_BUILD_DIR))

from prepare_runtime_data import DELIVERY_MANIFEST, selected_runtime_files  # noqa: E402

PACK_FORMAT_VERSION = 4
STATE_SCHEMA_VERSION = 1
PACK_FILENAME = "brur-world-data.zip"
HASH_STATE_FILENAME = "runtime_file_hashes.json"
PROGRESS_INTERVAL_SECONDS = 2.0
RANDOM_ACCESS_STORED_FILES = frozenset(
    {
        "routing.brg",
        "routing_snap.brs",
        "routing_geometry.brh",
    }
)

BMC2_MAGIC = b"BMC2"
BMC3_MAGIC = b"BMC3"
BMC2_VERSION = 2
BMC3_VERSION = 3
BMC_HEADER = struct.Struct("<4sII")
BMC2_RECORD = struct.Struct("<ffI")
BMC2_VERTEX = struct.Struct("<ffffffBBBB")
BMC3_RECORD = struct.Struct("<ffIB3x12s")
BMC3_VERTEX = struct.Struct("<hhhbbB")
BMC3_SCALE_M = 0.1
BMC3_MODE_COMPACT = 0
BMC3_MODE_RAW = 1


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _stat_identity(path: Path) -> dict[str, int]:
    stat = path.stat()
    return {
        "dev": int(stat.st_dev),
        "ino": int(stat.st_ino),
        "size": int(stat.st_size),
        "mtime_ns": int(stat.st_mtime_ns),
        "ctime_ns": int(stat.st_ctime_ns),
    }


def _read_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def _write_json_atomic(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(value, indent=2, sort_keys=True), encoding="utf-8")
    os.replace(temp, path)


def _human_bytes(value: int) -> str:
    amount = float(max(value, 0))
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if amount < 1024.0 or unit == "TB":
            return f"{amount:.1f} {unit}"
        amount /= 1024.0
    return f"{amount:.1f} TB"


def _runtime_category(relative_name: str) -> str:
    parts = Path(relative_name).parts
    return parts[0] if len(parts) > 1 else "root-files"


def _compression_for_runtime_file(relative_name: str) -> int:
    """Keep seek-heavy runtime datasets directly seekable inside the mounted ZIP pack."""
    if relative_name in RANDOM_ACCESS_STORED_FILES:
        return zipfile.ZIP_STORED
    return zipfile.ZIP_DEFLATED


def _report_runtime_footprint(identities: dict[str, dict[str, int]]) -> None:
    by_category: dict[str, int] = defaultdict(int)
    for relative_name, identity in identities.items():
        by_category[_runtime_category(relative_name)] += identity["size"]
    total = sum(by_category.values())
    print(f"WINDOWS_RUNTIME_RAW_TOTAL={_human_bytes(total)}", flush=True)
    for category, size in sorted(by_category.items(), key=lambda item: (-item[1], item[0])):
        print(
            f"WINDOWS_RUNTIME_RAW category={category} size={_human_bytes(size)} percent={100.0 * size / max(total, 1):.1f}",
            flush=True,
        )


def _cleanup_obsolete_pack_cache(cache_dir: Path) -> None:
    """Remove only cache files whose own metadata identifies an obsolete pack format."""
    pack_dir = cache_dir / "runtime-packs"
    if not pack_dir.is_dir():
        return
    freed = 0
    removed = 0
    for metadata_path in pack_dir.glob("*.zip.json"):
        metadata = _read_json(metadata_path)
        version = metadata.get("pack_format_version")
        if not isinstance(version, int) or version == PACK_FORMAT_VERSION:
            continue
        pack_path = metadata_path.with_suffix("")
        fingerprint = str(metadata.get("fingerprint", ""))
        if pack_path.is_file():
            freed += pack_path.stat().st_size
            pack_path.unlink()
            removed += 1
        metadata_path.unlink(missing_ok=True)
        if len(fingerprint) == 64:
            for shipping_path in pack_dir.glob(f"{fingerprint}.shipping-base-v*.zip*"):
                if shipping_path.is_file():
                    freed += shipping_path.stat().st_size
                    shipping_path.unlink()
                    removed += 1
    if removed:
        print(
            f"WINDOWS_RUNTIME_CACHE_CLEANUP removed={removed} freed={_human_bytes(freed)} obsolete_format_only=true",
            flush=True,
        )


def _quantize_i16(value: float) -> int | None:
    quantized = round(value / BMC3_SCALE_M)
    if quantized < -32768 or quantized > 32767:
        return None
    return int(quantized)


def _quantize_normal(value: float) -> int:
    return max(-127, min(127, round(value * 127.0)))


def _compact_bmc2(payload: bytes) -> tuple[bytes, int, int]:
    """Convert one BMC2 chunk to BMC3; oversized/irregular records stay raw inside BMC3."""
    if len(payload) < BMC_HEADER.size:
        raise ValueError("short BMC2 header")
    magic, version, vertex_count = BMC_HEADER.unpack_from(payload, 0)
    if magic != BMC2_MAGIC or version != BMC2_VERSION:
        return payload, 0, 0

    output = bytearray(BMC_HEADER.pack(BMC3_MAGIC, BMC3_VERSION, vertex_count))
    offset = BMC_HEADER.size
    compact_records = 0
    raw_records = 0
    decoded_vertices = 0
    while offset < len(payload):
        if offset + BMC2_RECORD.size > len(payload):
            raise ValueError("truncated BMC2 record header")
        record_x, record_z, record_vertices = BMC2_RECORD.unpack_from(payload, offset)
        offset += BMC2_RECORD.size
        blob_size = record_vertices * BMC2_VERTEX.size
        if offset + blob_size > len(payload):
            raise ValueError("truncated BMC2 vertex payload")
        raw_blob = payload[offset : offset + blob_size]
        offset += blob_size
        decoded_vertices += record_vertices

        colors: list[bytes] = []
        compact_vertices = bytearray()
        compact_ok = True
        for index in range(record_vertices):
            vertex_offset = index * BMC2_VERTEX.size
            x, y, z, nx, ny, nz, r, g, b, a = BMC2_VERTEX.unpack_from(raw_blob, vertex_offset)
            color = bytes((r, g, b, a))
            if color not in colors:
                colors.append(color)
            if len(colors) > 3:
                compact_ok = False
                break
            qx = _quantize_i16(x)
            qy = _quantize_i16(y)
            qz = _quantize_i16(z)
            if qx is None or qy is None or qz is None:
                compact_ok = False
                break
            color_index = colors.index(color)
            roof = 1 if ny > 0.5 else 0
            meta = color_index | (roof << 2)
            compact_vertices += BMC3_VERTEX.pack(
                qx,
                qy,
                qz,
                _quantize_normal(nx),
                _quantize_normal(nz),
                meta,
            )

        palette = b"".join(colors[:3]).ljust(12, b"\0")
        if compact_ok:
            output += BMC3_RECORD.pack(record_x, record_z, record_vertices, BMC3_MODE_COMPACT, palette)
            output += compact_vertices
            compact_records += 1
        else:
            output += BMC3_RECORD.pack(record_x, record_z, record_vertices, BMC3_MODE_RAW, b"\0" * 12)
            output += raw_blob
            raw_records += 1

    if offset != len(payload) or decoded_vertices != vertex_count:
        raise ValueError("BMC2 vertex count mismatch")
    return bytes(output), compact_records, raw_records


class _Progress:
    def __init__(self, stage: str, total_items: int, total_bytes: int | None = None) -> None:
        self.stage = stage
        self.total_items = max(total_items, 1)
        self.total_bytes = total_bytes
        self.started = time.monotonic()
        self.last_print = 0.0

    def update(self, items: int, processed_bytes: int = 0, *, force: bool = False) -> None:
        now = time.monotonic()
        if not force and now - self.last_print < PROGRESS_INTERVAL_SECONDS:
            return
        self.last_print = now
        percent = min(100.0, 100.0 * items / self.total_items)
        elapsed = now - self.started
        detail = f"{items:,}/{self.total_items:,} files"
        if self.total_bytes is not None:
            detail += f" | {_human_bytes(processed_bytes)}/{_human_bytes(self.total_bytes)}"
        print(
            f"[runtime-pack] {self.stage:<11} {percent:5.1f}% | {detail} | {elapsed:.1f}s",
            flush=True,
        )


def _verified_hashes(source: Path, cache_dir: Path) -> tuple[dict[str, str], int, int]:
    source = source.resolve()
    selected = selected_runtime_files(source)
    state_path = cache_dir / HASH_STATE_FILENAME
    previous = _read_json(state_path)
    previous_files = previous.get("files", {}) if previous.get("source_root") == str(source) else {}
    if not isinstance(previous_files, dict):
        previous_files = {}

    if previous_files:
        print("WINDOWS BUILD — CHECKING CACHED WORLD PACK", flush=True)
        print("[runtime-pack] unchanged data will use SHIPPING only", flush=True)
    else:
        print("WINDOWS BUILD — PACKING + SHIPPING", flush=True)
        print("[runtime-pack] first/new world pack: checking files before packing", flush=True)

    identities: dict[str, dict[str, int]] = {}
    check_progress = _Progress("checking", len(selected))
    for number, relative in enumerate(selected, 1):
        relative_name = relative.as_posix()
        identities[relative_name] = _stat_identity(source / relative)
        check_progress.update(number)
    check_progress.update(len(selected), force=True)
    _report_runtime_footprint(identities)

    hashes: dict[str, str] = {}
    next_files: dict[str, dict[str, Any]] = {}
    reused = 0
    rehashed = 0
    bytes_hashed = 0
    files_to_hash = []
    for relative in selected:
        relative_name = relative.as_posix()
        identity = identities[relative_name]
        cached = previous_files.get(relative_name)
        if (
            isinstance(cached, dict)
            and cached.get("identity") == identity
            and isinstance(cached.get("sha256"), str)
            and len(cached["sha256"]) == 64
        ):
            hashes[relative_name] = cached["sha256"]
            next_files[relative_name] = {"identity": identity, "sha256": cached["sha256"]}
            reused += 1
        else:
            files_to_hash.append(relative)

    hash_total_bytes = sum(identities[path.as_posix()]["size"] for path in files_to_hash)
    if files_to_hash:
        print(
            f"[runtime-pack] {len(files_to_hash):,} file(s) need hashing; "
            f"{_human_bytes(hash_total_bytes)} will be read",
            flush=True,
        )
        hash_progress = _Progress("hashing", len(files_to_hash), hash_total_bytes)
        for number, relative in enumerate(files_to_hash, 1):
            relative_name = relative.as_posix()
            digest = sha256(source / relative)
            hashes[relative_name] = digest
            next_files[relative_name] = {"identity": identities[relative_name], "sha256": digest}
            rehashed += 1
            bytes_hashed += identities[relative_name]["size"]
            hash_progress.update(number, bytes_hashed)
        hash_progress.update(len(files_to_hash), bytes_hashed, force=True)
    else:
        print("[runtime-pack] hashing      100.0% | 0 files changed — no content reread", flush=True)

    _write_json_atomic(
        state_path,
        {
            "schema_version": STATE_SCHEMA_VERSION,
            "source_root": str(source),
            "files": next_files,
        },
    )
    return hashes, reused, rehashed


def _fingerprint(hashes: dict[str, str]) -> str:
    digest = hashlib.sha256()
    digest.update(f"brur-windows-runtime-pack-v{PACK_FORMAT_VERSION}\0".encode("utf-8"))
    for relative_name in sorted(hashes):
        digest.update(relative_name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(hashes[relative_name].encode("ascii"))
        digest.update(b"\0")
    return digest.hexdigest()


def _pack_metadata_path(pack_path: Path) -> Path:
    return pack_path.with_suffix(pack_path.suffix + ".json")


def _pack_cache_valid(pack_path: Path, fingerprint: str) -> bool:
    metadata = _read_json(_pack_metadata_path(pack_path))
    if metadata.get("schema_version") != STATE_SCHEMA_VERSION:
        return False
    if metadata.get("pack_format_version") != PACK_FORMAT_VERSION:
        return False
    if metadata.get("fingerprint") != fingerprint:
        return False
    if not pack_path.is_file() or metadata.get("pack_identity") != _stat_identity(pack_path):
        return False
    if not zipfile.is_zipfile(pack_path):
        return False
    try:
        with zipfile.ZipFile(pack_path, "r") as archive:
            return f"world_data/{DELIVERY_MANIFEST}" in archive.namelist()
    except (OSError, zipfile.BadZipFile):
        return False


def _verify_built_pack(pack_path: Path) -> None:
    with zipfile.ZipFile(pack_path, "r") as archive:
        entries = [entry for entry in archive.infolist() if not entry.is_dir()]
        total_bytes = sum(entry.file_size for entry in entries)
        progress = _Progress("verifying", len(entries), total_bytes)
        verified_bytes = 0
        for number, entry in enumerate(entries, 1):
            with archive.open(entry, "r") as handle:
                while chunk := handle.read(1024 * 1024):
                    verified_bytes += len(chunk)
            progress.update(number, verified_bytes)
        progress.update(len(entries), verified_bytes, force=True)


def _build_pack(source: Path, pack_path: Path, fingerprint: str, hashes: dict[str, str]) -> None:
    source = source.resolve()
    pack_path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=pack_path.name + ".", suffix=".tmp", dir=pack_path.parent)
    os.close(fd)
    temp_path = Path(temp_name)
    transformed_source_bytes = 0
    transformed_output_bytes = 0
    compact_records = 0
    raw_records = 0
    try:
        total_bytes = sum((source / relative_name).stat().st_size for relative_name in hashes)
        packed_bytes = 0
        progress = _Progress("packing", len(hashes), total_bytes)
        with zipfile.ZipFile(
            temp_path,
            "w",
            compression=zipfile.ZIP_DEFLATED,
            compresslevel=6,
            allowZip64=True,
        ) as archive:
            for number, relative_name in enumerate(sorted(hashes), 1):
                path = source / relative_name
                archive_name = f"world_data/{relative_name}"
                if relative_name.startswith("building_mesh_lod/") and path.suffix == ".bmc":
                    original = path.read_bytes()
                    compact, record_count, fallback_count = _compact_bmc2(original)
                    archive.writestr(archive_name, compact)
                    transformed_source_bytes += len(original)
                    transformed_output_bytes += len(compact)
                    compact_records += record_count
                    raw_records += fallback_count
                else:
                    archive.write(
                        path,
                        archive_name,
                        compress_type=_compression_for_runtime_file(relative_name),
                    )
                packed_bytes += path.stat().st_size
                progress.update(number, packed_bytes)
            archive.writestr(
                f"world_data/{DELIVERY_MANIFEST}",
                json.dumps(
                    {
                        "schema_version": 3,
                        "pack_format_version": PACK_FORMAT_VERSION,
                        "fingerprint": fingerprint,
                        "files": sorted(hashes),
                        "sha256": hashes,
                        "storage": {
                            "stored_random_access": sorted(RANDOM_ACCESS_STORED_FILES),
                            "default": "deflate",
                        },
                        "transforms": {
                            "building_mesh_lod": "BMC2=>BMC3:q0.1m:norm8:palette3",
                        },
                    },
                    indent=2,
                    sort_keys=True,
                ),
            )
        progress.update(len(hashes), packed_bytes, force=True)
        print(
            "WINDOWS_RUNTIME_STORAGE random_access=stored files="
            + ",".join(sorted(RANDOM_ACCESS_STORED_FILES)),
            flush=True,
        )
        if transformed_source_bytes:
            reduction = 100.0 * (1.0 - transformed_output_bytes / transformed_source_bytes)
            print(
                "WINDOWS_RUNTIME_TRANSFORM category=building_mesh_lod "
                f"source={_human_bytes(transformed_source_bytes)} compact={_human_bytes(transformed_output_bytes)} "
                f"reduction={reduction:.1f}% compact_records={compact_records} raw_fallback_records={raw_records}",
                flush=True,
            )
        _verify_built_pack(temp_path)
        os.replace(temp_path, pack_path)
    finally:
        temp_path.unlink(missing_ok=True)

    _write_json_atomic(
        _pack_metadata_path(pack_path),
        {
            "schema_version": STATE_SCHEMA_VERSION,
            "pack_format_version": PACK_FORMAT_VERSION,
            "fingerprint": fingerprint,
            "pack_identity": _stat_identity(pack_path),
        },
    )


def prepare_cached_runtime_pack(source: Path, cache_dir: Path) -> dict[str, Any]:
    source = source.resolve()
    cache_dir = cache_dir.expanduser().resolve()
    cache_dir.mkdir(parents=True, exist_ok=True)
    _cleanup_obsolete_pack_cache(cache_dir)

    started = time.monotonic()
    hashes, reused_hashes, rehashed_files = _verified_hashes(source, cache_dir)
    identity_seconds = time.monotonic() - started
    fingerprint = _fingerprint(hashes)
    pack_dir = cache_dir / "runtime-packs"
    pack_path = pack_dir / f"{fingerprint}.zip"

    pack_started = time.monotonic()
    cache_hit = _pack_cache_valid(pack_path, fingerprint)
    if cache_hit:
        print("WINDOWS BUILD — SHIPPING", flush=True)
        print("[runtime-pack] reusable world pack unchanged — skipping packing", flush=True)
    else:
        print("WINDOWS BUILD — PACKING + SHIPPING", flush=True)
        print("[runtime-pack] building reusable world pack with seekable routing and compact building chunks", flush=True)
        _build_pack(source, pack_path, fingerprint, hashes)
    pack_seconds = time.monotonic() - pack_started

    report = {
        "schema_version": 1,
        "pack_format_version": PACK_FORMAT_VERSION,
        "pack_path": str(pack_path),
        "pack_filename": PACK_FILENAME,
        "fingerprint": fingerprint,
        "runtime_files": hashes,
        "stored_random_access_files": sorted(RANDOM_ACCESS_STORED_FILES),
        "cache_hit": cache_hit,
        "hashes_reused": reused_hashes,
        "files_rehashed": rehashed_files,
        "identity_seconds": round(identity_seconds, 6),
        "pack_seconds": round(pack_seconds, 6),
    }
    print(
        "WINDOWS_RUNTIME_PACK="
        f"{'HIT' if cache_hit else 'MISS'} fingerprint={fingerprint[:12]} "
        f"files={len(hashes)} hashes_reused={reused_hashes} rehashed={rehashed_files} "
        f"identity_s={identity_seconds:.3f} pack_s={pack_seconds:.3f}",
        flush=True,
    )
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Authoritative generated world_data directory")
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=Path(os.environ.get("BRUR_WINDOWS_CACHE_DIR", "~/.cache/brur-world/windows-build")),
    )
    parser.add_argument("--output-info", type=Path, required=True)
    args = parser.parse_args()

    report = prepare_cached_runtime_pack(args.source, args.cache_dir)
    _write_json_atomic(args.output_info.resolve(), report)


if __name__ == "__main__":
    main()
