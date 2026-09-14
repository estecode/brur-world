#!/usr/bin/env python3
"""Build BRM2 background from the shared assembled-area source cache."""
from __future__ import annotations

from pathlib import Path

from area_source_cache import area_source_cache_valid
from build_background import build_background


def build_background_sources(area_source: Path, output: Path) -> dict:
    if not area_source_cache_valid(area_source):
        raise ValueError(f"background requires a valid assembled-area cache: {area_source}")
    return build_background(area_source, output)
