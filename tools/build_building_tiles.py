#!/usr/bin/env python3
"""Build and validate bounded runtime building tiles derived from authoritative buildings JSONL.

Dependencies:
- Reads world_data/buildings.jsonl and manifest.json produced by the existing offline pipeline.
- Writes only the derived building_tiles runtime representation and manifest metadata.
- Does not read the Sweden PBF or create independent building truth.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import shutil
import time
from collections import OrderedDict
from pathlib import Path
from typing import TextIO

DEFAULT_TILE_SIZE = 2_000.0
DEFAULT_MAX_OPEN = 32
BUILDING_TILE_FORMAT_VERSION = 1


class BuildingTileWriter:
    def __init__(self, directory: Path, tile_size: float, max_open: int = DEFAULT_MAX_OPEN) -> None:
        if tile_size <= 0.0:
            raise ValueError("building tile size must be positive")
        self.directory = directory
        self.tile_size = tile_size
        self.max_open = max_open
        stamp = f"{os.getpid()}-{time.time_ns()}"
        self.write_directory = directory.parent / f".{directory.name}.build-{stamp}"
        self.write_directory.mkdir(parents=True, exist_ok=False)
        self.files: OrderedDict[tuple[int, int], TextIO] = OrderedDict()
        self.records = 0

    def write(self, record: dict) -> None:
        x = float(record["x"])
        y = float(record["y"])
        key = (math.floor(x / self.tile_size), math.floor(y / self.tile_size))
        handle = self.files.pop(key, None)
        if handle is None:
            handle = (self.write_directory / f"{key[0]}_{key[1]}.jsonl").open("a", encoding="utf-8")
        self.files[key] = handle
        handle.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
        self.records += 1
        if len(self.files) > self.max_open:
            _, oldest = self.files.popitem(last=False)
            oldest.close()

    def close(self) -> None:
        for handle in self.files.values():
            handle.close()
        self.files.clear()

    def publish(self) -> None:
        self.close()
        stale: Path | None = None
        if self.directory.exists():
            stale = self.directory.parent / f".{self.directory.name}.old-{os.getpid()}-{time.time_ns()}"
            self.directory.rename(stale)
        try:
            self.write_directory.rename(self.directory)
        except Exception:
            if stale is not None and stale.exists() and not self.directory.exists():
                stale.rename(self.directory)
            raise
        if stale is not None and stale.exists():
            shutil.rmtree(stale)

    def cleanup(self) -> None:
        self.close()
        if self.write_directory.exists():
            shutil.rmtree(self.write_directory)


def _builder_sha256() -> str:
    return hashlib.sha256(Path(__file__).read_bytes()).hexdigest()


def building_tiles_cache_valid(world_dir: Path, tile_size: float = DEFAULT_TILE_SIZE) -> bool:
    """Return whether the derived cache matches its authoritative source and this builder contract."""
    manifest_path = world_dir / "manifest.json"
    buildings_path = world_dir / "buildings.jsonl"
    tile_dir = world_dir / "building_tiles"
    if not manifest_path.is_file() or not buildings_path.is_file() or not tile_dir.is_dir():
        return False
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        source_stat = buildings_path.stat()
        features = manifest.get("features", {})
        if features.get("building_tiles_dir") != "building_tiles":
            return False
        if float(features.get("building_tile_size", 0.0)) != float(tile_size):
            return False
        if int(features.get("building_tile_format_version", 0)) != BUILDING_TILE_FORMAT_VERSION:
            return False
        if int(features.get("runtime_buildings_total", 0)) <= 0:
            return False
        if int(features.get("building_tiles_source_size", -1)) != source_stat.st_size:
            return False
        if int(features.get("building_tiles_source_mtime_ns", -1)) != source_stat.st_mtime_ns:
            return False
        if features.get("building_tiles_builder_sha256") != _builder_sha256():
            return False
        return next(tile_dir.glob("*.jsonl"), None) is not None
    except (OSError, TypeError, ValueError):
        return False


def build_building_tiles(world_dir: Path, tile_size: float = DEFAULT_TILE_SIZE) -> dict:
    manifest_path = world_dir / "manifest.json"
    buildings_path = world_dir / "buildings.jsonl"
    if not manifest_path.is_file():
        raise SystemExit(f"missing manifest: {manifest_path}")
    if not buildings_path.is_file():
        raise SystemExit(f"missing authoritative building export: {buildings_path}")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    source_stat = buildings_path.stat()
    output_dir = world_dir / "building_tiles"
    writer = BuildingTileWriter(output_dir, tile_size)
    started = time.monotonic()
    success = False
    try:
        with buildings_path.open("r", encoding="utf-8") as source:
            for line_number, line in enumerate(source, 1):
                if not line.strip():
                    continue
                try:
                    record = json.loads(line)
                except json.JSONDecodeError as exc:
                    raise SystemExit(f"invalid buildings.jsonl at line {line_number}: {exc}") from exc
                if "x" not in record or "y" not in record:
                    raise SystemExit(f"building record {line_number} is missing x/y")
                writer.write(record)
        writer.publish()
        success = True
    finally:
        if not success:
            writer.cleanup()

    features = dict(manifest.get("features", {}))
    features["building_tiles_dir"] = "building_tiles"
    features["building_tile_size"] = tile_size
    features["building_tile_format_version"] = BUILDING_TILE_FORMAT_VERSION
    features["building_tiles_source_size"] = source_stat.st_size
    features["building_tiles_source_mtime_ns"] = source_stat.st_mtime_ns
    features["building_tiles_builder_sha256"] = _builder_sha256()
    features["runtime_buildings_total"] = writer.records
    manifest["features"] = features
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    report = {
        "source": "buildings.jsonl",
        "source_rebuilt": False,
        "tile_size": tile_size,
        "format_version": BUILDING_TILE_FORMAT_VERSION,
        "records": writer.records,
        "tile_count": len(list(output_dir.glob("*.jsonl"))),
        "elapsed_s": time.monotonic() - started,
    }
    print(
        f"[building-tiles] records={report['records']:,} tiles={report['tile_count']:,} "
        f"tile_size={tile_size:.0f}m elapsed={report['elapsed_s']:.1f}s",
        flush=True,
    )
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("world_dir", type=Path, nargs="?", default=Path("world_data"))
    parser.add_argument("--tile-size", type=float, default=DEFAULT_TILE_SIZE)
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit successfully only when the existing cache matches the source and builder contract",
    )
    args = parser.parse_args()
    if args.check:
        valid = building_tiles_cache_valid(args.world_dir, args.tile_size)
        print(f"[building-tiles] cache={'valid' if valid else 'invalid'}", flush=True)
        raise SystemExit(0 if valid else 1)
    build_building_tiles(args.world_dir, args.tile_size)


if __name__ == "__main__":
    main()
