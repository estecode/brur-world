"""Resolve offline builder inputs through the shared OSM source-cache boundary.

Dependencies:
- Uses osm_source_cache.py for authoritative `.osm.pbf` inputs.
- Leaves generated source-cache blocks and small fixture sources unchanged.
"""

from __future__ import annotations

from pathlib import Path

from osm_source_cache import CACHE_DIR_NAME, build_source_caches


def resolve_route_source(source: Path, output: Path, route: str) -> Path:
    """Return a route-local OSM source, caching authoritative PBF input when needed."""
    source = Path(source)
    output = Path(output)
    # Semantic cache blocks are themselves `.osm.pbf`. They are the source
    # adapter boundary for downstream builders and must never recursively be
    # treated as a new authoritative PBF input.
    if source.parent.name == CACHE_DIR_NAME:
        return source
    if source.name.endswith(".osm.pbf"):
        return build_source_caches(source, output / CACHE_DIR_NAME, (route,))[route]
    return source
