"""Decode normalized highway source facts for BRUR offline builders."""
from __future__ import annotations

from pathlib import Path
from typing import Iterator

from normalized_source_facts import iter_facts, validate
from routing_graph import WayInput
from world_common import project

SCHEMA = 1


def validate_highways(path: Path) -> dict[str, int | str]:
    return validate(path, SCHEMA)


def iter_highway_ways(path: Path) -> Iterator[WayInput]:
    validate_highways(path)
    for fact in iter_facts(path, SCHEMA):
        node_ids = [int(value) for value in fact.get("node_ids", [])]
        lonlat_raw = fact.get("lonlat", [])
        coordinates = [(float(point[0]), float(point[1])) for point in lonlat_raw]
        if len(node_ids) != len(coordinates) or len(node_ids) < 2:
            raise ValueError(f"invalid highway fact way {fact.get('osm_id')}")
        tags = {str(key): str(value) for key, value in fact.get("tags", {}).items()}
        yield WayInput(int(fact["osm_id"]), node_ids, coordinates, tags)


def projected_points(way: WayInput) -> list[tuple[float, float]]:
    return [project(lon, lat) for lon, lat in way.coordinates]
