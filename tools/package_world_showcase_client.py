#!/usr/bin/env python3
"""Build a self-contained #126 client ZIP from an exported Windows runtime.

Dependencies:
- Reuses prepare_world_showcase.py to derive only the Malmö/Göteborg/Stockholm runtime subset.
- Reads existing local world_data runtime exports; it never reads or rebuilds the Sweden PBF.
- Requires an already-exported Windows EXE/PCK pair plus build_info.json.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import tempfile
import zipfile
from pathlib import Path

from prepare_world_showcase import prepare


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _find_binary_pair(binary_dir: Path) -> tuple[Path, Path]:
    exes = sorted(binary_dir.glob("*.exe"))
    if len(exes) != 1:
        raise SystemExit(f"expected exactly one Windows EXE in {binary_dir}, found {len(exes)}")
    exe = exes[0]
    pck = binary_dir / f"{exe.stem}.pck"
    if not pck.is_file():
        raise SystemExit(f"missing matching PCK for {exe.name}: {pck}")
    return exe, pck


def package_client(binary_dir: Path, world_data: Path, output_zip: Path) -> dict:
    binary_dir = binary_dir.resolve()
    world_data = world_data.resolve()
    build_info_path = binary_dir / "build_info.json"
    if not build_info_path.is_file():
        raise SystemExit(f"missing build_info.json in {binary_dir}")

    build_info = json.loads(build_info_path.read_text(encoding="utf-8"))
    commit = str(build_info.get("commit", "")).strip()
    if not commit:
        raise SystemExit("build_info.json is missing commit")

    exe, pck = _find_binary_pair(binary_dir)
    output_zip.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="brur-client-bundle-") as directory:
        staging = Path(directory) / "BRUR"
        runtime_data = staging / "runtime_data"
        staging.mkdir(parents=True)

        shutil.copy2(exe, staging / exe.name)
        shutil.copy2(pck, staging / pck.name)
        shutil.copy2(build_info_path, staging / "build_info.json")

        report = prepare(world_data, runtime_data)
        runtime_files = sorted(path for path in runtime_data.iterdir() if path.is_file())
        runtime_hashes = {path.name: _sha256(path) for path in runtime_files}
        source_manifest = world_data / "manifest.json"
        bundle_info = {
            "pr": build_info.get("pr"),
            "commit": commit,
            "godot": build_info.get("godot"),
            "platform": build_info.get("platform"),
            "runtime_source": report.get("source"),
            "runtime_source_rebuilt": report.get("source_rebuilt"),
            "source_manifest_sha256": _sha256(source_manifest),
            "runtime_files": runtime_hashes,
        }
        (staging / "client_bundle_info.json").write_text(
            json.dumps(bundle_info, indent=2, sort_keys=True), encoding="utf-8"
        )

        with zipfile.ZipFile(output_zip, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for path in sorted(staging.rglob("*")):
                if path.is_file():
                    archive.write(path, Path("BRUR") / path.relative_to(staging))

    print(
        f"[world-showcase-client] ready zip={output_zip} commit={commit[:12]} "
        f"runtime_files={len(runtime_hashes)} selected={report['selected_records']}"
    )
    return bundle_info


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("binary_dir", type=Path, help="Extracted Windows artifact directory containing EXE/PCK/build_info.json")
    parser.add_argument("world_data", type=Path, help="Local existing world_data directory")
    parser.add_argument("--output", type=Path, required=True, help="Complete client ZIP to create")
    args = parser.parse_args()
    package_client(args.binary_dir, args.world_data, args.output)


if __name__ == "__main__":
    main()
