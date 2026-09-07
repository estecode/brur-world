"""Shared projection and world-build constants for Brur World offline exporters."""

from __future__ import annotations

import math
from pathlib import Path

TILE_SIZE = 32_000.0
EARTH_RADIUS = 6_378_137.0


def project(lon: float, lat: float) -> tuple[float, float]:
    """Project WGS84 lon/lat to Web Mercator meters."""
    lat = max(-85.05112878, min(85.05112878, lat))
    x = EARTH_RADIUS * math.radians(lon)
    y = EARTH_RADIUS * math.log(math.tan(math.pi / 4.0 + math.radians(lat) / 2.0))
    return x, y


def ensure_pbf(path: Path) -> None:
    """Fail early when the requested OSM source file is missing."""
    if not path.is_file():
        raise SystemExit(f"PBF not found: {path}")
