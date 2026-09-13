#!/usr/bin/env python3
"""Stages only production runtime world data for the self-contained Windows export.

Dependencies:
- Reads already-built authoritative world_data from the mapped checkout.
- Copies only runtime representations consumed by production; it never rebuilds source truth.
- Excludes OSM source caches and heavy rebuild-only JSONL intermediates.
"""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

REQUIRED_FILES = (
    "manifest.json",
    "background.brmap",
    "city_light_density.jsonl",
    "routing.brg",
    "routing_snap.brs",
    "routing_geometry.brh",
    "search_index.bsi",
    "traffic_signals.json",
)

OPTIONAL_FILES = (
    "routing_stats.json",
)

REQUIRED_DIRS = (
    "lod0",
    "lod1",
    "lod2",
    "poi_tiles",
    "building_tiles",
)

DELIVERY_MANIFEST = "windows_runtime_manifest.json"


def _require_nonempty_file(path: Path) -> None:
    if not path.is_file() or path.stat().st_size <= 0:
        raise SystemExit(f"missing production runtime file: {path}")


def _require_nonempty_dir(path: Path) -> None:
    if not path.is_dir() or not any(candidate.is_file() for candidate in path.rglob("*")):
        raise SystemExit(f"missing or empty production runtime directory: {path}")


def prepare_runtime_data(source: Path, output: Path) -> list[str]:
    source = source.resolve()
    output = output.resolve()

    for name in REQUIRED_FILES:
        _require_nonempty_file(source / name)
    for name in REQUIRED_DIRS:
        _require_nonempty_dir(source / name)

    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)

    copied: list[str] = []
    for name in REQUIRED_FILES:
        shutil.copy2(source / name, output / name)
        copied.append(name)
    for name in OPTIONAL_FILES:
        candidate = source / name
        if candidate.is_file() and candidate.stat().st_size > 0:
            shutil.copy2(candidate, output / name)
            copied.append(name)
    for name in REQUIRED_DIRS:
        shutil.copytree(source / name, output / name)
        copied.extend(
            path.relative_to(output).as_posix()
            for path in sorted((output / name).rglob("*"))
            if path.is_file()
        )

    if any(path.name in {"buildings.jsonl", "search_index.jsonl", "pois.jsonl"} for path in output.rglob("*")):
        raise SystemExit("rebuild-only JSONL source leaked into Windows runtime data")
    if (output / "osm_source_cache").exists():
        raise SystemExit("OSM source cache leaked into Windows runtime data")

    payload = {
        "schema_version": 1,
        "files": sorted(copied),
    }
    (output / DELIVERY_MANIFEST).write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    copied.append(DELIVERY_MANIFEST)

    print(f"[windows-runtime-data] ready files={len(copied)} output={output}", flush=True)
    return copied


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Existing authoritative world_data directory")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    prepare_runtime_data(args.source, args.output)


if __name__ == "__main__":
    main()
