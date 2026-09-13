#!/usr/bin/env python3
"""Packages a validated Windows export with a cached external runtime world-data resource pack.

Dependencies:
- Reads an EXE/PCK pair produced by the selected revision's Windows target.
- Reads runtime-pack identity/hashes produced by runtime_pack.py; it never rebuilds or rehashes world truth.
- Reuses a cached client ZIP base whose single compressed member is the stable mountable runtime pack.
- The target has already verified that mounting the runtime pack exposes res://world_data.
- Uses only Python standard library modules.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import tempfile
import time
import zipfile
from pathlib import Path
from typing import Any

FORMAT_VERSION = 4
SHIPPING_CACHE_VERSION = 1
RUNTIME_DELIVERY = "resource_pack:brur-world-data.zip=>res://world_data"


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


def _human_bytes(value: int) -> str:
    amount = float(max(value, 0))
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if amount < 1024.0 or unit == "TB":
            return f"{amount:.1f} {unit}"
        amount /= 1024.0
    return f"{amount:.1f} TB"


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


def find_binary_pair(binary_dir: Path) -> tuple[Path, Path]:
    exes = sorted(binary_dir.glob("*.exe"))
    if len(exes) != 1:
        raise SystemExit(f"expected exactly one Windows EXE in {binary_dir}, found {len(exes)}")
    exe = exes[0]
    pck = binary_dir / f"{exe.stem}.pck"
    if not pck.is_file():
        raise SystemExit(f"missing matching PCK for {exe.name}: {pck}")
    return exe, pck


def resolve_runtime_pack_info_path(path: Path) -> Path:
    """Accept the current info-file contract and the pre-#226 launcher directory contract."""
    resolved = path.resolve()
    if resolved.is_dir():
        resolved = resolved / "runtime_pack_info.json"
    return resolved


def load_runtime_pack_info(path: Path) -> dict[str, Any]:
    if not path.is_file():
        raise SystemExit(f"missing runtime pack info: {path}")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid runtime pack info: {path}: {exc}") from exc
    if not isinstance(value, dict) or value.get("schema_version") != 1:
        raise SystemExit("unsupported runtime pack info schema")

    pack_path = Path(str(value.get("pack_path", ""))).expanduser().resolve()
    pack_filename = str(value.get("pack_filename", ""))
    fingerprint = str(value.get("fingerprint", ""))
    runtime_files = value.get("runtime_files")
    if pack_filename != "brur-world-data.zip":
        raise SystemExit(f"unexpected runtime pack filename: {pack_filename}")
    if len(fingerprint) != 64:
        raise SystemExit("runtime pack info is missing a full fingerprint")
    if not isinstance(runtime_files, dict) or not runtime_files:
        raise SystemExit("runtime pack info has no runtime file hashes")
    if not pack_path.is_file() or pack_path.stat().st_size <= 0:
        raise SystemExit(f"runtime pack is missing or empty: {pack_path}")
    if not zipfile.is_zipfile(pack_path):
        raise SystemExit(f"runtime pack is not a valid ZIP resource pack: {pack_path}")
    with zipfile.ZipFile(pack_path, "r") as archive:
        if "world_data/windows_runtime_manifest.json" not in archive.namelist():
            raise SystemExit("runtime pack is missing its delivery manifest")
        if any(
            not entry.is_dir() and entry.compress_type != zipfile.ZIP_STORED
            for entry in archive.infolist()
        ):
            raise SystemExit("runtime pack must keep entries stored for monolithic delivery compression")

    normalized_hashes: dict[str, str] = {}
    for relative_name, digest in runtime_files.items():
        if not isinstance(relative_name, str) or not isinstance(digest, str) or len(digest) != 64:
            raise SystemExit("runtime pack info contains an invalid file hash")
        normalized_hashes[relative_name] = digest

    result = dict(value)
    result["pack_path"] = str(pack_path)
    result["runtime_files"] = normalized_hashes
    return result


def _shipping_base_path(runtime_pack: Path, fingerprint: str) -> Path:
    return runtime_pack.parent / f"{fingerprint}.shipping-base-v{SHIPPING_CACHE_VERSION}.zip"


def _shipping_metadata_path(shipping_base: Path) -> Path:
    return shipping_base.with_suffix(shipping_base.suffix + ".json")


def _shipping_base_valid(
    shipping_base: Path,
    runtime_pack: Path,
    pack_filename: str,
    fingerprint: str,
) -> bool:
    metadata = _read_json(_shipping_metadata_path(shipping_base))
    if metadata.get("shipping_cache_version") != SHIPPING_CACHE_VERSION:
        return False
    if metadata.get("fingerprint") != fingerprint:
        return False
    if metadata.get("runtime_pack_identity") != _stat_identity(runtime_pack):
        return False
    if not shipping_base.is_file() or metadata.get("shipping_base_identity") != _stat_identity(shipping_base):
        return False
    try:
        with zipfile.ZipFile(shipping_base, "r") as archive:
            entries = [entry for entry in archive.infolist() if not entry.is_dir()]
            if len(entries) != 1:
                return False
            member = entries[0]
            return (
                member.filename == f"BRUR/{pack_filename}"
                and member.compress_type == zipfile.ZIP_DEFLATED
                and member.file_size == runtime_pack.stat().st_size
            )
    except (OSError, zipfile.BadZipFile):
        return False


def _build_shipping_base(
    shipping_base: Path,
    runtime_pack: Path,
    pack_filename: str,
    fingerprint: str,
) -> None:
    shipping_base.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(
        prefix=shipping_base.name + ".",
        suffix=".tmp",
        dir=shipping_base.parent,
    )
    os.close(fd)
    temp_path = Path(temp_name)
    try:
        print(
            "WINDOWS BUILD — PACKING DELIVERY PAYLOAD",
            flush=True,
        )
        print(
            f"[windows-package] compressing reusable world pack as one {_human_bytes(runtime_pack.stat().st_size)} member",
            flush=True,
        )
        started = time.monotonic()
        with zipfile.ZipFile(
            temp_path,
            "w",
            compression=zipfile.ZIP_DEFLATED,
            compresslevel=6,
            allowZip64=True,
        ) as archive:
            archive.write(runtime_pack, f"BRUR/{pack_filename}")
        with zipfile.ZipFile(temp_path, "r") as archive:
            member = archive.getinfo(f"BRUR/{pack_filename}")
            if member.compress_type != zipfile.ZIP_DEFLATED:
                raise SystemExit("shipping base did not compress the runtime pack")
            if member.file_size != runtime_pack.stat().st_size:
                raise SystemExit("shipping base runtime member size does not match source pack")
        os.replace(temp_path, shipping_base)
        elapsed = time.monotonic() - started
        print(
            f"[windows-package] delivery payload packed {_human_bytes(shipping_base.stat().st_size)} | {elapsed:.1f}s",
            flush=True,
        )
    finally:
        temp_path.unlink(missing_ok=True)

    _write_json_atomic(
        _shipping_metadata_path(shipping_base),
        {
            "shipping_cache_version": SHIPPING_CACHE_VERSION,
            "fingerprint": fingerprint,
            "runtime_pack_identity": _stat_identity(runtime_pack),
            "shipping_base_identity": _stat_identity(shipping_base),
        },
    )


def prepare_shipping_base(
    runtime_pack: Path,
    pack_filename: str,
    fingerprint: str,
) -> tuple[Path, bool]:
    shipping_base = _shipping_base_path(runtime_pack, fingerprint)
    cache_hit = _shipping_base_valid(shipping_base, runtime_pack, pack_filename, fingerprint)
    if cache_hit:
        print(
            f"WINDOWS_SHIPPING_PAYLOAD=HIT fingerprint={fingerprint[:12]} size={_human_bytes(shipping_base.stat().st_size)}",
            flush=True,
        )
        return shipping_base, True

    _build_shipping_base(shipping_base, runtime_pack, pack_filename, fingerprint)
    print(
        f"WINDOWS_SHIPPING_PAYLOAD=MISS fingerprint={fingerprint[:12]} size={_human_bytes(shipping_base.stat().st_size)}",
        flush=True,
    )
    return shipping_base, False


def package_client(
    binary_dir: Path,
    runtime_pack_info_path: Path,
    build_info_path: Path,
    source_manifest: Path,
    output_zip: Path,
) -> dict:
    binary_dir = binary_dir.resolve()
    runtime_pack_info_path = resolve_runtime_pack_info_path(runtime_pack_info_path)
    build_info_path = build_info_path.resolve()
    source_manifest = source_manifest.resolve()
    output_zip = output_zip.expanduser().resolve()

    if not build_info_path.is_file():
        raise SystemExit(f"missing build info: {build_info_path}")
    if not source_manifest.is_file():
        raise SystemExit(f"missing authoritative source manifest: {source_manifest}")

    build_info = json.loads(build_info_path.read_text(encoding="utf-8"))
    commit = str(build_info.get("commit", "")).strip()
    repository = str(build_info.get("repository", "")).strip()
    if len(commit) != 40 or not repository:
        raise SystemExit("build info must contain repository and full 40-character commit SHA")

    exe, pck = find_binary_pair(binary_dir)
    runtime_info = load_runtime_pack_info(runtime_pack_info_path)
    runtime_pack = Path(runtime_info["pack_path"])
    pack_filename = runtime_info["pack_filename"]
    hashes = runtime_info["runtime_files"]
    fingerprint = runtime_info["fingerprint"]
    output_zip.parent.mkdir(parents=True, exist_ok=True)

    shipping_base, shipping_cache_hit = prepare_shipping_base(runtime_pack, pack_filename, fingerprint)

    final_build_info = dict(build_info)
    final_build_info["client_ready"] = True
    final_build_info["world_data_source_manifest_sha256"] = sha256(source_manifest)
    final_build_info["runtime_files"] = hashes
    final_build_info["runtime_pack_fingerprint"] = fingerprint
    final_build_info["runtime_pack_cache_hit"] = bool(runtime_info.get("cache_hit", False))
    final_build_info["shipping_payload_cache_hit"] = shipping_cache_hit
    final_build_info["runtime_delivery"] = RUNTIME_DELIVERY
    final_build_info["packaging_format_version"] = FORMAT_VERSION

    bundle_info = {
        "schema_version": 1,
        "repository": repository,
        "commit": commit,
        "short_commit": commit[:12],
        "ref": final_build_info.get("ref"),
        "pr": final_build_info.get("pr"),
        "issue": final_build_info.get("issue"),
        "world_data_source_manifest_sha256": final_build_info["world_data_source_manifest_sha256"],
        "runtime_files": hashes,
        "runtime_pack_fingerprint": fingerprint,
        "runtime_delivery": RUNTIME_DELIVERY,
        "shipping_payload_cache_hit": shipping_cache_hit,
        "packaging_format_version": FORMAT_VERSION,
    }

    output_zip.unlink(missing_ok=True)
    shutil.copy2(shipping_base, output_zip)
    with zipfile.ZipFile(output_zip, "a", compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as archive:
        archive.write(exe, f"BRUR/{exe.name}")
        archive.write(pck, f"BRUR/{pck.name}")
        archive.writestr(
            "BRUR/build_info.json",
            json.dumps(final_build_info, indent=2, sort_keys=True),
        )
        archive.writestr(
            "BRUR/client_bundle_info.json",
            json.dumps(bundle_info, indent=2, sort_keys=True),
        )
        archive.writestr("BRUR/logs/", "")

    with zipfile.ZipFile(output_zip, "r") as archive:
        names = set(archive.namelist())
        required = {
            f"BRUR/{exe.name}",
            f"BRUR/{pck.name}",
            f"BRUR/{pack_filename}",
            "BRUR/build_info.json",
            "BRUR/client_bundle_info.json",
            "BRUR/logs/",
        }
        missing = required - names
        if missing:
            raise SystemExit(f"client ZIP validation failed; missing: {sorted(missing)}")
        if any(name.startswith("BRUR/runtime_data/") for name in names):
            raise SystemExit("client ZIP duplicated runtime data beside the resource pack")
        runtime_members = [
            entry for entry in archive.infolist() if entry.filename == f"BRUR/{pack_filename}"
        ]
        if len(runtime_members) != 1:
            raise SystemExit("client ZIP must contain exactly one runtime resource pack")
        runtime_member = runtime_members[0]
        if runtime_member.compress_type != zipfile.ZIP_DEFLATED:
            raise SystemExit("client ZIP did not use the cached monolithic compressed runtime payload")
        if runtime_member.file_size != runtime_pack.stat().st_size:
            raise SystemExit("client ZIP runtime payload size does not match cached runtime pack")

    print(
        f"[windows-package] ready zip={output_zip} size={_human_bytes(output_zip.stat().st_size)} "
        f"commit={commit[:12]} runtime_files={len(hashes)} delivery={RUNTIME_DELIVERY} "
        f"fingerprint={fingerprint[:12]} shipping_cache={'HIT' if shipping_cache_hit else 'MISS'}"
    )
    return bundle_info


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("binary_dir", type=Path)
    parser.add_argument("runtime_pack_info", type=Path)
    parser.add_argument("build_info", type=Path)
    parser.add_argument("source_manifest", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    package_client(
        args.binary_dir,
        args.runtime_pack_info,
        args.build_info,
        args.source_manifest,
        args.output,
    )


if __name__ == "__main__":
    main()
