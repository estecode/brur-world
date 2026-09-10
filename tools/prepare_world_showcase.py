#!/usr/bin/env python3
"""Prepare disposable multi-city building and map data from existing runtime exports.

Dependencies:
- Reads only world_data/manifest.json, world_data/buildings.jsonl, and world_data/background.brmap.
- Does not read Sweden PBF or rebuild authoritative world/routing/search data.
- Writes experiment-only cache files outside world_data.
"""

from __future__ import annotations

import argparse
import json
import math
import shutil
import struct
import time
from pathlib import Path

CITY_CENTERS = {
    "malmo": (1_447_576.3943775708, 7_480_180.845685549),
    "goteborg": (1_333_006.3744531337, 7_906_413.516421634),
    "stockholm": (2_011_387.3513473428, 8_251_904.234165725),
}
DEFAULT_RADIUS_M = 1_500.0
BACKGROUND_RADIUS_M = 50_000.0
PROGRESS_INTERVAL = 250_000
MAP_MAGIC = b"BRM2"
MAP_TRIANGLE = struct.Struct("<Bffffff")


def _prepare_background(source_dir: Path, output_dir: Path, radius_m: float) -> dict[str, int]:
    path = source_dir / "background.brmap"
    if not path.is_file():
        raise SystemExit(f"missing existing map runtime export: {path}")

    outputs: dict[str, object] = {}
    counts = {city: 0 for city in CITY_CENTERS}
    try:
        for city in CITY_CENTERS:
            handle = (output_dir / f"background_{city}.brmap").open("wb+")
            handle.write(MAP_MAGIC)
            handle.write(struct.pack("<I", 0))
            outputs[city] = handle

        with path.open("rb") as source:
            if source.read(4) != MAP_MAGIC:
                raise SystemExit(f"invalid background map magic: {path}")
            header = source.read(4)
            if len(header) != 4:
                raise SystemExit(f"truncated background map header: {path}")
            triangle_count = struct.unpack("<I", header)[0]
            for index in range(triangle_count):
                raw = source.read(MAP_TRIANGLE.size)
                if len(raw) != MAP_TRIANGLE.size:
                    raise SystemExit(f"truncated background map at triangle {index}")
                _kind, x1, y1, x2, y2, x3, y3 = MAP_TRIANGLE.unpack(raw)
                min_x = min(x1, x2, x3)
                max_x = max(x1, x2, x3)
                min_y = min(y1, y2, y3)
                max_y = max(y1, y2, y3)
                for city, (cx, cy) in CITY_CENTERS.items():
                    if (
                        max_x >= cx - radius_m
                        and min_x <= cx + radius_m
                        and max_y >= cy - radius_m
                        and min_y <= cy + radius_m
                    ):
                        outputs[city].write(raw)
                        counts[city] += 1
    finally:
        for city, handle in outputs.items():
            handle.seek(4)
            handle.write(struct.pack("<I", counts[city]))
            handle.close()

    missing = [city for city, count in counts.items() if count <= 0]
    if missing:
        raise SystemExit("existing background.brmap contained no local map triangles for: " + ", ".join(missing))
    return counts


def prepare(
    source_dir: Path,
    output_dir: Path,
    radius_m: float = DEFAULT_RADIUS_M,
    background_radius_m: float = BACKGROUND_RADIUS_M,
) -> dict:
    manifest_path = source_dir / "manifest.json"
    buildings_path = source_dir / "buildings.jsonl"
    if not manifest_path.is_file():
        raise SystemExit(f"missing manifest: {manifest_path}")
    if not buildings_path.is_file():
        raise SystemExit(
            f"missing existing building runtime export: {buildings_path}; "
            "the showcase intentionally does not rebuild it"
        )

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    tile_size = float(manifest.get("tile_size", 32_000.0))
    if tile_size <= 0.0:
        raise SystemExit("invalid tile_size in manifest")

    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True)

    files: dict[tuple[int, int], object] = {}
    selected_by_city = {name: 0 for name in CITY_CENTERS}
    scanned = 0
    selected = 0
    started = time.monotonic()

    try:
        with buildings_path.open("r", encoding="utf-8") as source:
            for line in source:
                scanned += 1
                if scanned % PROGRESS_INTERVAL == 0:
                    elapsed = max(0.001, time.monotonic() - started)
                    print(
                        f"[world-showcase] scanned={scanned:,} selected={selected:,} "
                        f"rate={scanned / elapsed:,.0f}/s",
                        flush=True,
                    )
                if not line.strip():
                    continue
                try:
                    record = json.loads(line)
                except json.JSONDecodeError as exc:
                    raise SystemExit(f"invalid buildings.jsonl at line {scanned}: {exc}") from exc

                x = float(record.get("x", math.inf))
                y = float(record.get("y", math.inf))
                matched_city = None
                for city, (cx, cy) in CITY_CENTERS.items():
                    if abs(x - cx) <= radius_m and abs(y - cy) <= radius_m:
                        matched_city = city
                        break
                if matched_city is None:
                    continue

                tx = math.floor(x / tile_size)
                ty = math.floor(y / tile_size)
                key = (tx, ty)
                handle = files.get(key)
                if handle is None:
                    handle = (output_dir / f"{tx}_{ty}.jsonl").open("w", encoding="utf-8")
                    files[key] = handle
                handle.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n")
                selected += 1
                selected_by_city[matched_city] += 1
    finally:
        for handle in files.values():
            handle.close()

    background_by_city = _prepare_background(source_dir, output_dir, background_radius_m)
    report = {
        "source": "world_data/buildings.jsonl + world_data/background.brmap",
        "source_rebuilt": False,
        "centers_absolute": {name: list(center) for name, center in CITY_CENTERS.items()},
        "radius_m": radius_m,
        "background_radius_m": background_radius_m,
        "tile_size": tile_size,
        "scanned_records": scanned,
        "selected_records": selected,
        "selected_by_city": selected_by_city,
        "background_triangles_by_city": background_by_city,
        "tile_count": len(files),
    }
    (output_dir / "showcase_manifest.json").write_text(json.dumps(report, indent=2), encoding="utf-8")

    missing = [name for name, count in selected_by_city.items() if count == 0]
    if missing:
        raise SystemExit(
            "existing buildings.jsonl contained no buildings in showcase radius for: "
            + ", ".join(missing)
        )

    print(
        f"[world-showcase] ready selected={selected:,} tiles={len(files)} "
        f"background={background_by_city} elapsed={time.monotonic() - started:.1f}s",
        flush=True,
    )
    return report


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_dir", type=Path, help="Existing world_data directory")
    parser.add_argument("--output", type=Path, required=True, help="Disposable showcase data directory")
    parser.add_argument("--radius-m", type=float, default=DEFAULT_RADIUS_M)
    parser.add_argument("--background-radius-m", type=float, default=BACKGROUND_RADIUS_M)
    args = parser.parse_args()
    prepare(args.source_dir, args.output, args.radius_m, args.background_radius_m)


if __name__ == "__main__":
    main()
