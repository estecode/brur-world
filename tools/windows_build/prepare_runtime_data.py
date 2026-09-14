#!/usr/bin/env python3
"""Selects the production runtime world-data subset used by Windows packaging.

Dependencies:
- Reads already-built authoritative world_data from the mapped checkout.
- Selects only runtime representations consumed by production; it never rebuilds source truth.
- Excludes OSM source caches and heavy rebuild-only intermediates.
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
    "road_surfaces",
    "poi_tiles",
    "building_mesh_lod",
)

DELIVERY_MANIFEST = "windows_runtime_manifest.json"


def _require_nonempty_file(path: Path) -> None:
    if not path.is_file() or path.stat().st_size <= 0:
        raise SystemExit(f"missing production runtime file: {path}")


def _require_nonempty_dir(path: Path) -> None:
    if not path.is_dir() or not any(candidate.is_file() for candidate in path.rglob("*")):
        raise SystemExit(f"missing or empty production runtime directory: {path}")


def selected_runtime_files(source: Path) -> list[Path]:
    """Return the exact production runtime files relative to ``source``."""
    source = source.resolve()
    for name in REQUIRED_FILES:
        _require_nonempty_file(source / name)
    for name in REQUIRED_DIRS:
        _require_nonempty_dir(source / name)

    selected: list[Path] = [Path(name) for name in REQUIRED_FILES]
    for name in OPTIONAL_FILES:
        candidate = source / name
        if candidate.is_file() and candidate.stat().st_size > 0:
            selected.append(Path(name))
    for name in REQUIRED_DIRS:
        selected.extend(
            path.relative_to(source)
            for path in sorted((source / name).rglob("*"))
            if path.is_file()
        )

    selected = sorted(set(selected), key=lambda path: path.as_posix())
    forbidden_names = {"buildings.jsonl", "search_index.jsonl", "pois.jsonl"}
    if any(path.name in forbidden_names for path in selected):
        raise SystemExit("rebuild-only JSONL source selected for Windows runtime data")
    if any(path.parts and path.parts[0] == "osm_source_cache" for path in selected):
        raise SystemExit("OSM source cache selected for Windows runtime data")
    if any(path.parts and path.parts[0] == "building_tiles" for path in selected):
        raise SystemExit("obsolete building_tiles selected instead of building_mesh_lod")
    return selected


def prepare_runtime_data(source: Path, output: Path) -> list[str]:
    """Compatibility helper that materializes the selected subset into ``output``."""
    source = source.resolve()
    output = output.resolve()
    selected = selected_runtime_files(source)

    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)

    copied: list[str] = []
    for relative in selected:
        destination = output / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / relative, destination)
        copied.append(relative.as_posix())

    payload = {
        "schema_version": 2,
        "files": copied,
    }
    (output / DELIVERY_MANIFEST).write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    copied.append(DELIVERY_MANIFEST)

    print(f"[windows-runtime-data] ready files={len(copied)} output={output}", flush=True)
    return copied


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Existing authoritative generated world_data directory")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    prepare_runtime_data(args.source, args.output)


if __name__ == "__main__":
    main()
