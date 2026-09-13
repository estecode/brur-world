#!/usr/bin/env python3
"""Packages a validated Windows export with a cached external runtime world-data resource pack.

Dependencies:
- Reads an EXE/PCK pair produced by the selected revision's Windows target.
- Reads runtime-pack identity/hashes produced by runtime_pack.py; it never rebuilds or rehashes world truth.
- The target has already verified that mounting the runtime pack exposes res://world_data.
- Uses only Python standard library modules.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from pathlib import Path
from typing import Any

FORMAT_VERSION = 3
RUNTIME_DELIVERY = "resource_pack:brur-world-data.zip=>res://world_data"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


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

    normalized_hashes: dict[str, str] = {}
    for relative_name, digest in runtime_files.items():
        if not isinstance(relative_name, str) or not isinstance(digest, str) or len(digest) != 64:
            raise SystemExit("runtime pack info contains an invalid file hash")
        normalized_hashes[relative_name] = digest

    result = dict(value)
    result["pack_path"] = str(pack_path)
    result["runtime_files"] = normalized_hashes
    return result


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

    final_build_info = dict(build_info)
    final_build_info["client_ready"] = True
    final_build_info["world_data_source_manifest_sha256"] = sha256(source_manifest)
    final_build_info["runtime_files"] = hashes
    final_build_info["runtime_pack_fingerprint"] = fingerprint
    final_build_info["runtime_pack_cache_hit"] = bool(runtime_info.get("cache_hit", False))
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
        "packaging_format_version": FORMAT_VERSION,
    }

    with zipfile.ZipFile(output_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as archive:
        archive.write(exe, f"BRUR/{exe.name}")
        archive.write(pck, f"BRUR/{pck.name}")
        archive.write(runtime_pack, f"BRUR/{pack_filename}", compress_type=zipfile.ZIP_STORED)
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
        runtime_member = archive.getinfo(f"BRUR/{pack_filename}")
        if runtime_member.compress_type != zipfile.ZIP_STORED:
            raise SystemExit("client ZIP recompressed the cached runtime resource pack")

    print(
        f"[windows-package] ready zip={output_zip} size={runtime_pack.stat().st_size + exe.stat().st_size + pck.stat().st_size} "
        f"commit={commit[:12]} runtime_files={len(hashes)} delivery={RUNTIME_DELIVERY} fingerprint={fingerprint[:12]}"
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
