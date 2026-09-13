#!/usr/bin/env python3
"""Packages a validated Windows export whose production world data is embedded in its PCK.

Dependencies:
- Reads an EXE/PCK pair produced by the selected revision's Windows target.
- Reads prepared runtime-data fingerprints and the authoritative source manifest; it never rebuilds world truth.
- The target has already verified the PCK exposes the prepared data at res://world_data.
- Uses only Python standard library modules.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import tempfile
import zipfile
from pathlib import Path

FORMAT_VERSION = 2
RUNTIME_DELIVERY = "embedded_pck:res://world_data"


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


def runtime_hashes(runtime_data: Path) -> dict[str, str]:
    files = sorted(path for path in runtime_data.rglob("*") if path.is_file())
    if not files:
        raise SystemExit(f"runtime data is empty: {runtime_data}")
    return {path.relative_to(runtime_data).as_posix(): sha256(path) for path in files}


def package_client(
    binary_dir: Path,
    runtime_data: Path,
    build_info_path: Path,
    source_manifest: Path,
    output_zip: Path,
) -> dict:
    binary_dir = binary_dir.resolve()
    runtime_data = runtime_data.resolve()
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
    hashes = runtime_hashes(runtime_data)
    output_zip.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="brur-windows-package-") as directory:
        staging = Path(directory) / "BRUR"
        logs = staging / "logs"
        staging.mkdir(parents=True)
        logs.mkdir()

        shutil.copy2(exe, staging / exe.name)
        shutil.copy2(pck, staging / pck.name)

        final_build_info = dict(build_info)
        final_build_info["client_ready"] = True
        final_build_info["world_data_source_manifest_sha256"] = sha256(source_manifest)
        final_build_info["runtime_files"] = hashes
        final_build_info["runtime_delivery"] = RUNTIME_DELIVERY
        final_build_info["packaging_format_version"] = FORMAT_VERSION
        (staging / "build_info.json").write_text(
            json.dumps(final_build_info, indent=2, sort_keys=True), encoding="utf-8"
        )

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
            "runtime_delivery": RUNTIME_DELIVERY,
            "packaging_format_version": FORMAT_VERSION,
        }
        (staging / "client_bundle_info.json").write_text(
            json.dumps(bundle_info, indent=2, sort_keys=True), encoding="utf-8"
        )

        with zipfile.ZipFile(output_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            archive.writestr("BRUR/logs/", "")
            for path in sorted(staging.rglob("*")):
                if path.is_file():
                    archive.write(path, Path("BRUR") / path.relative_to(staging))

        with zipfile.ZipFile(output_zip, "r") as archive:
            names = set(archive.namelist())
            required = {
                f"BRUR/{exe.name}",
                f"BRUR/{pck.name}",
                "BRUR/build_info.json",
                "BRUR/client_bundle_info.json",
                "BRUR/logs/",
            }
            missing = required - names
            if missing:
                raise SystemExit(f"client ZIP validation failed; missing: {sorted(missing)}")
            if any(name.startswith("BRUR/runtime_data/") for name in names):
                raise SystemExit("client ZIP duplicated embedded runtime data beside the PCK")

    print(
        f"[windows-package] ready zip={output_zip} commit={commit[:12]} "
        f"runtime_files={len(hashes)} delivery={RUNTIME_DELIVERY}"
    )
    return bundle_info


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("binary_dir", type=Path)
    parser.add_argument("runtime_data", type=Path)
    parser.add_argument("build_info", type=Path)
    parser.add_argument("source_manifest", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    package_client(
        args.binary_dir,
        args.runtime_data,
        args.build_info,
        args.source_manifest,
        args.output,
    )


if __name__ == "__main__":
    main()
