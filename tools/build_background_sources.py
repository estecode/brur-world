#!/usr/bin/env python3
"""Compose BRM2 background from independently cached OSM source blocks.

All background semantics remain owned by build_background.py. This adapter only
feeds the same accumulator/OSM handler from the background-area, coastline and
admin-boundary cache blocks before publishing the existing BRM2 artifact.
"""

from __future__ import annotations

import json
import time
from datetime import datetime, timezone
from pathlib import Path

from build_background import (
    BACKGROUND_HEADER,
    LAND,
    BackgroundAccumulator,
    BackgroundHandler,
    solve_coastline_land,
)
from world_common import TILE_SIZE, ensure_pbf


def _now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def _log(message: str) -> None:
    print(f"[{_now()}] [background] {message}", flush=True)


def build_background_sources(
    background_areas: Path,
    coastlines: Path,
    admin_boundaries: Path,
    output: Path,
) -> dict:
    sources = (background_areas, coastlines, admin_boundaries)
    for source in sources:
        ensure_pbf(source)

    started = time.monotonic()
    _log(
        "START cache-blocks="
        f"{background_areas.name},{coastlines.name},{admin_boundaries.name}"
    )
    accumulator = BackgroundAccumulator()
    handler = BackgroundHandler(accumulator)

    for source in sources:
        phase_started = time.monotonic()
        _log(f"READ source={source.name}")
        handler.apply_file(str(source), locations=True)
        _log(f"READ-DONE source={source.name} elapsed={time.monotonic() - phase_started:.1f}s")

    if handler.admin_polygons:
        land = solve_coastline_land(handler.admin_polygons, handler.coastlines)
        accumulator.add_geometry(LAND, land)

    output.mkdir(parents=True, exist_ok=True)
    destination = output / "background.brmap"
    temp = destination.with_suffix(destination.suffix + ".tmp")
    with temp.open("wb") as handle:
        handle.write(BACKGROUND_HEADER.pack(b"BRM2", accumulator.triangles))
        handle.write(accumulator.payload)
    temp.replace(destination)

    manifest_path = output / "manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.is_file() else {}
    except (OSError, json.JSONDecodeError):
        manifest = {}
    if "bounds" not in manifest and accumulator.triangles > 0:
        manifest["bounds"] = [accumulator.min_x, accumulator.min_y, accumulator.max_x, accumulator.max_y]
        manifest["origin_x"] = (accumulator.min_x + accumulator.max_x) * 0.5
        manifest["origin_y"] = (accumulator.min_y + accumulator.max_y) * 0.5
        manifest["tile_size"] = TILE_SIZE
    manifest["background_format"] = "BRM2"
    manifest["background"] = {
        "triangles": accumulator.triangles,
        "land_mask_source": "osm_natural_coastline",
        "admin_clip_areas": len(handler.admin_polygons),
        "coastline_ways": len(handler.coastlines),
        "areas": {
            "land": accumulator.counts[0],
            "farmland": accumulator.counts[1],
            "forest": accumulator.counts[2],
            "urban": accumulator.counts[3],
            "water": accumulator.counts[4],
        },
        "rejected_water_like": accumulator.rejected_water_like,
        "rejected_invalid_water": accumulator.rejected_invalid_water,
        "rejected_coastal_water": accumulator.rejected_coastal_water,
        "source_cache_blocks": [source.name for source in sources],
    }
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    _log(
        f"DONE triangles={accumulator.triangles:,} coastlines={len(handler.coastlines):,} "
        f"bytes={destination.stat().st_size:,} elapsed={time.monotonic() - started:.1f}s"
    )
    return manifest
