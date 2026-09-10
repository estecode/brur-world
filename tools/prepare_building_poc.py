#!/usr/bin/env python3
"""Prepare an ephemeral Malmö tile cache from the existing buildings.jsonl runtime export.

Dependencies:
- Reads only world_data/manifest.json and world_data/buildings.jsonl.
- Does not read the Sweden PBF or rebuild any existing world/routing/search dataset.
- Writes disposable POC cache files outside world_data.
"""

from __future__ import annotations

import argparse
import json
import math
import shutil
import time
from pathlib import Path

MALMO_X = 1_447_576.3943775708
MALMO_Y = 7_480_180.845685549
DEFAULT_RADIUS_M = 6_000.0
PROGRESS_INTERVAL = 250_000


def prepare(source_dir: Path, output_dir: Path, radius_m: float = DEFAULT_RADIUS_M) -> dict:
    manifest_path = source_dir / "manifest.json"
    buildings_path = source_dir / "buildings.jsonl"
    if not manifest_path.is_file():
        raise SystemExit(f"missing manifest: {manifest_path}")
    if not buildings_path.is_file():
        raise SystemExit(
            f"missing existing building runtime export: {buildings_path}; "
            "this POC intentionally does not rebuild it"
        )

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    tile_size = float(manifest.get("tile_size", 32_000.0))
    if tile_size <= 0.0:
        raise SystemExit("invalid tile_size in manifest")

    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True)

    min_x = MALMO_X - radius_m
    max_x = MALMO_X + radius_m
    min_y = MALMO_Y - radius_m
    max_y = MALMO_Y + radius_m
    files: dict[tuple[int, int], object] = {}
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
                        f"[building-poc] scanned={scanned:,} selected={selected:,} "
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
                if x < min_x or x > max_x or y < min_y or y > max_y:
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
    finally:
        for handle in files.values():
            handle.close()

    result = {
        "source": "world_data/buildings.jsonl",
        "source_rebuilt": False,
        "center_absolute": [MALMO_X, MALMO_Y],
        "radius_m": radius_m,
        "tile_size": tile_size,
        "scanned_records": scanned,
        "selected_records": selected,
        "tile_count": len(files),
    }
    (output_dir / "poc_manifest.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(
        f"[building-poc] ready selected={selected:,} tiles={len(files)} "
        f"elapsed={time.monotonic() - started:.1f}s",
        flush=True,
    )
    if selected == 0:
        raise SystemExit("existing buildings.jsonl contained no Malmö buildings in the POC radius")
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_dir", type=Path, help="Existing world_data directory")
    parser.add_argument("--output", type=Path, required=True, help="Disposable POC tile cache directory")
    parser.add_argument("--radius-m", type=float, default=DEFAULT_RADIUS_M)
    args = parser.parse_args()
    prepare(args.source_dir, args.output, args.radius_m)


if __name__ == "__main__":
    main()
