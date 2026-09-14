"""Resolve offline builder inputs through the shared normalized source-cache boundary."""
from __future__ import annotations

from pathlib import Path

from osm_source_cache import CACHE_DIR_NAME, build_source_caches


def resolve_route_source(source: Path, output: Path, route: str) -> Path:
    source = Path(source); output = Path(output)
    if source.parent.name == CACHE_DIR_NAME or source.suffix in {".brfacts", ".baf"}:
        return source
    if source.name.endswith(".osm.pbf"):
        return build_source_caches(source, output / CACHE_DIR_NAME, (route,))[route]
    return source
