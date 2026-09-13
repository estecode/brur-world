#!/usr/bin/env python3
"""Builds and reuses a content-addressed Windows runtime world-data resource pack.

Dependencies:
- Uses prepare_runtime_data.py as the single Windows runtime-selection contract.
- Reads authoritative generated world_data without rebuilding it.
- Stores only local verification metadata/hashes and derived ZIP resource packs in a cache.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import tempfile
import time
import zipfile
from pathlib import Path
from typing import Any

WINDOWS_BUILD_DIR = Path(__file__).resolve().parent
if str(WINDOWS_BUILD_DIR) not in sys.path:
    sys.path.insert(0, str(WINDOWS_BUILD_DIR))

from prepare_runtime_data import DELIVERY_MANIFEST, selected_runtime_files  # noqa: E402

PACK_FORMAT_VERSION = 1
STATE_SCHEMA_VERSION = 1
PACK_FILENAME = "brur-world-data.zip"
HASH_STATE_FILENAME = "runtime_file_hashes.json"
PROGRESS_INTERVAL_SECONDS = 2.0


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
    total_bytes = 0
    check_progress = _Progress("checking", len(selected))
    for number, relative in enumerate(selected, 1):
        relative_name = relative.as_posix()
        identity = _stat_identity(source / relative)
        identities[relative_name] = identity
        total_bytes += identity["size"]
        check_progress.update(number)
    check_progress.update(len(selected), force=True)

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
                archive.write(path, f"world_data/{relative_name}")
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
                    },
                    indent=2,
                    sort_keys=True,
                ),
            )
        progress.update(len(hashes), packed_bytes, force=True)
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
        print("[runtime-pack] building reusable world pack", flush=True)
        _build_pack(source, pack_path, fingerprint, hashes)
    pack_seconds = time.monotonic() - pack_started

    report = {
        "schema_version": 1,
        "pack_format_version": PACK_FORMAT_VERSION,
        "pack_path": str(pack_path),
        "pack_filename": PACK_FILENAME,
        "fingerprint": fingerprint,
        "runtime_files": hashes,
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
