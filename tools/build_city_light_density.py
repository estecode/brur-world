#!/usr/bin/env python3
"""Build compact POI-density input for nighttime city-light presentation.

Dependencies:
- Reads filtered runtime POI tiles produced by build_features.py.
- Writes a derived density dataset consumed by the Godot city-light adapter.
- Does not read OSM directly or introduce an independent city/world truth.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

CELL_SIZE_M = 2000.0
OUTPUT_NAME = "city_light_density.jsonl"
FORMAT = "CLD1"


def build_city_light_density(world_data: Path) -> dict:
    poi_tiles = world_data / "poi_tiles"
    if not poi_tiles.is_dir():
        raise FileNotFoundError(f"missing runtime POI tiles: {poi_tiles}")

    counts: dict[tuple[int, int], int] = {}
    poi_count = 0
    for path in sorted(poi_tiles.glob("*.jsonl")):
        with path.open("r", encoding="utf-8") as file:
            for line in file:
                if not line.strip():
                    continue
                record = json.loads(line)
                x = float(record["x"])
                y = float(record["y"])
                key = (math.floor(x / CELL_SIZE_M), math.floor(y / CELL_SIZE_M))
                counts[key] = counts.get(key, 0) + 1
                poi_count += 1

    output = world_data / OUTPUT_NAME
    with output.open("w", encoding="utf-8") as file:
        for (cell_x, cell_y), count in sorted(counts.items()):
            record = {
                "x": (cell_x + 0.5) * CELL_SIZE_M,
                "y": (cell_y + 0.5) * CELL_SIZE_M,
                "count": count,
            }
            file.write(json.dumps(record, separators=(",", ":")) + "\n")

    manifest_path = world_data / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.is_file() else {}
    manifest["city_light_density"] = {
        "format": FORMAT,
        "file": OUTPUT_NAME,
        "cell_size_m": CELL_SIZE_M,
        "cells": len(counts),
        "runtime_pois": poi_count,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    print(
        f"[city-light-density] cells={len(counts):,} runtime_pois={poi_count:,} "
        f"cell_size={CELL_SIZE_M:.0f}m output={output}",
        flush=True,
    )
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("world_data", type=Path, nargs="?", default=Path("world_data"))
    args = parser.parse_args()
    build_city_light_density(args.world_data)


if __name__ == "__main__":
    main()
