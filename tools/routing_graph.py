"""Build and serialize Brur World's compact routing graph.

Dependencies:
- Pure Python; receives already-decoded OSM ways from the offline source reader.
- Used by build_routing.py and automatic tests. Runtime consumers only need BRG1.
"""

from __future__ import annotations

import math
import struct
from collections import Counter
from dataclasses import dataclass, field
from enum import IntEnum
from pathlib import Path
from typing import Iterable, Mapping, Sequence

from world_common import project


MAGIC = b"BRG1"
HEADER = struct.Struct("<4sII")
NODE_RECORD = struct.Struct("<qddffII")
EDGE_RECORD = struct.Struct("<qIIIffBBBBbB")

FLAG_AGAINST_ONEWAY = 1 << 0
FLAG_BRIDGE = 1 << 1
FLAG_TUNNEL = 1 << 2


class AccessClass(IntEnum):
    NORMAL = 0
    DESTINATION = 1
    RESTRICTED = 2
    FORBIDDEN_NORMAL = 3


class AccessReason(IntEnum):
    DEFAULT = 0
    NON_CAR_HIGHWAY = 1
    ACCESS_NO = 2
    VEHICLE_NO = 3
    MOTOR_VEHICLE_NO = 4
    MOTORCAR_NO = 5
    PRIVATE = 6
    DESTINATION = 7
    LIMITED_ACCESS = 8


class SpeedSource(IntEnum):
    OSM = 0
    FALLBACK = 1


class RoutingProfile(IntEnum):
    NORMAL = 0
    PURSUIT = 1
    GETAWAY = 2


HIGHWAY_TYPES = (
    "motorway",
    "motorway_link",
    "trunk",
    "trunk_link",
    "primary",
    "primary_link",
    "secondary",
    "secondary_link",
    "tertiary",
    "tertiary_link",
    "unclassified",
    "residential",
    "living_street",
    "service",
    "road",
    "track",
    "cycleway",
    "footway",
    "path",
    "pedestrian",
    "bridleway",
    "steps",
    "busway",
    "escape",
    "raceway",
)
ROAD_CLASS = {name: index for index, name in enumerate(HIGHWAY_TYPES)}
ROAD_CLASS_NAME = {value: key for key, value in ROAD_CLASS.items()}

NON_CAR_HIGHWAYS = frozenset({"cycleway", "footway", "path", "pedestrian", "bridleway", "steps"})

# These are routing fallbacks only. Explicit OSM maxspeed always wins.
DEFAULT_SPEED_KMH = {
    "motorway": 110.0,
    "motorway_link": 70.0,
    "trunk": 90.0,
    "trunk_link": 70.0,
    "primary": 70.0,
    "primary_link": 50.0,
    "secondary": 60.0,
    "secondary_link": 50.0,
    "tertiary": 50.0,
    "tertiary_link": 40.0,
    "unclassified": 50.0,
    "residential": 40.0,
    "living_street": 20.0,
    "service": 30.0,
    "road": 40.0,
    "track": 20.0,
    "cycleway": 20.0,
    "footway": 8.0,
    "path": 10.0,
    "pedestrian": 8.0,
    "bridleway": 10.0,
    "steps": 5.0,
    "busway": 50.0,
    "escape": 40.0,
    "raceway": 100.0,
}

_NO_VALUES = frozenset({"no", "0", "false"})
_PRIVATE_VALUES = frozenset({"private"})
_DESTINATION_VALUES = frozenset({"destination"})
_LIMITED_VALUES = frozenset({"customers", "delivery", "agricultural", "forestry", "permit"})
_YES_VALUES = frozenset({"yes", "1", "true", "permissive", "designated"})


@dataclass(frozen=True)
class SpeedInfo:
    kmh: float
    source: SpeedSource
    raw: str | None = None
    unknown_raw: str | None = None


@dataclass(frozen=True)
class AccessInfo:
    access_class: AccessClass
    reason: AccessReason


@dataclass(frozen=True)
class GraphNode:
    osm_id: int
    lon: float
    lat: float
    x: float
    y: float
    adjacency_offset: int
    adjacency_count: int


@dataclass(frozen=True)
class GraphEdge:
    way_id: int
    segment_index: int
    source_index: int
    target_index: int
    length_m: float
    speed_kmh: float
    road_class: int
    access_class: AccessClass
    flags: int
    speed_source: SpeedSource
    layer: int
    access_reason: AccessReason

    @property
    def against_oneway(self) -> bool:
        return bool(self.flags & FLAG_AGAINST_ONEWAY)

    @property
    def bridge(self) -> bool:
        return bool(self.flags & FLAG_BRIDGE)

    @property
    def tunnel(self) -> bool:
        return bool(self.flags & FLAG_TUNNEL)


@dataclass
class GraphBuildStats:
    way_count: int = 0
    skipped_way_count: int = 0
    explicit_speed_edges: int = 0
    fallback_speed_edges: int = 0
    restricted_edges: int = 0
    against_oneway_edges: int = 0
    fallback_by_highway: Counter[str] = field(default_factory=Counter)
    unknown_maxspeed: Counter[str] = field(default_factory=Counter)

    def to_dict(self) -> dict:
        return {
            "way_count": self.way_count,
            "skipped_way_count": self.skipped_way_count,
            "explicit_speed_edges": self.explicit_speed_edges,
            "fallback_speed_edges": self.fallback_speed_edges,
            "restricted_edges": self.restricted_edges,
            "against_oneway_edges": self.against_oneway_edges,
            "fallback_by_highway": dict(sorted(self.fallback_by_highway.items())),
            "unknown_maxspeed": dict(sorted(self.unknown_maxspeed.items())),
        }


@dataclass(frozen=True)
class RoutingGraph:
    nodes: tuple[GraphNode, ...]
    edges: tuple[GraphEdge, ...]

    def stable_edge_id(self, edge: GraphEdge) -> str:
        source_osm = self.nodes[edge.source_index].osm_id
        target_osm = self.nodes[edge.target_index].osm_id
        return f"w{edge.way_id}:{source_osm}>{target_osm}:{edge.segment_index}"


@dataclass(frozen=True)
class WayInput:
    way_id: int
    node_ids: Sequence[int]
    coordinates: Sequence[tuple[float, float]]  # lon, lat
    tags: Mapping[str, str]


def parse_maxspeed(value: str | None, highway: str) -> SpeedInfo:
    fallback = DEFAULT_SPEED_KMH[highway]
    if value is None or not str(value).strip():
        return SpeedInfo(fallback, SpeedSource.FALLBACK)

    raw = str(value).strip()
    text = raw.lower().replace(",", ".")
    first = text.split(";", 1)[0].strip()

    number_text = first
    multiplier = 1.0
    if first.endswith("mph"):
        number_text = first[:-3].strip()
        multiplier = 1.609344
    elif first.endswith("knots"):
        number_text = first[:-5].strip()
        multiplier = 1.852
    elif first.endswith("knot"):
        number_text = first[:-4].strip()
        multiplier = 1.852
    elif first.endswith("km/h"):
        number_text = first[:-4].strip()
    elif first.endswith("kph"):
        number_text = first[:-3].strip()

    try:
        value_kmh = float(number_text) * multiplier
    except ValueError:
        return SpeedInfo(fallback, SpeedSource.FALLBACK, raw=raw, unknown_raw=raw)

    if not math.isfinite(value_kmh) or value_kmh <= 0.0:
        return SpeedInfo(fallback, SpeedSource.FALLBACK, raw=raw, unknown_raw=raw)
    return SpeedInfo(value_kmh, SpeedSource.OSM, raw=raw)


def parse_oneway(tags: Mapping[str, str]) -> int:
    value = str(tags.get("oneway", "")).strip().lower()
    if value in {"yes", "1", "true"}:
        return 1
    if value in {"-1", "reverse"}:
        return -1
    if value in {"no", "0", "false"}:
        return 0
    if str(tags.get("junction", "")).strip().lower() == "roundabout":
        return 1
    return 0


def classify_access(highway: str, tags: Mapping[str, str]) -> AccessInfo:
    normalized = {key: str(value).strip().lower() for key, value in tags.items()}

    for key, reason in (
        ("motorcar", AccessReason.MOTORCAR_NO),
        ("motor_vehicle", AccessReason.MOTOR_VEHICLE_NO),
        ("vehicle", AccessReason.VEHICLE_NO),
        ("access", AccessReason.ACCESS_NO),
    ):
        if normalized.get(key) in _NO_VALUES:
            return AccessInfo(AccessClass.FORBIDDEN_NORMAL, reason)

    explicit_vehicle = normalized.get("motorcar") or normalized.get("motor_vehicle")
    if explicit_vehicle in _YES_VALUES:
        return AccessInfo(AccessClass.NORMAL, AccessReason.DEFAULT)

    for key in ("motorcar", "motor_vehicle", "vehicle", "access"):
        value = normalized.get(key)
        if value in _PRIVATE_VALUES:
            return AccessInfo(AccessClass.FORBIDDEN_NORMAL, AccessReason.PRIVATE)
        if value in _DESTINATION_VALUES:
            return AccessInfo(AccessClass.DESTINATION, AccessReason.DESTINATION)
        if value in _LIMITED_VALUES:
            return AccessInfo(AccessClass.RESTRICTED, AccessReason.LIMITED_ACCESS)

    if highway in NON_CAR_HIGHWAYS:
        return AccessInfo(AccessClass.FORBIDDEN_NORMAL, AccessReason.NON_CAR_HIGHWAY)
    return AccessInfo(AccessClass.NORMAL, AccessReason.DEFAULT)


def is_edge_allowed(edge: GraphEdge, profile: RoutingProfile) -> bool:
    if profile == RoutingProfile.NORMAL:
        return not edge.against_oneway and edge.access_class in {AccessClass.NORMAL, AccessClass.DESTINATION}
    return True


def geodesic_distance_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    """Return haversine distance between lon/lat pairs in metres."""
    lon1, lat1 = map(math.radians, a)
    lon2, lat2 = map(math.radians, b)
    dlon = lon2 - lon1
    dlat = lat2 - lat1
    h = math.sin(dlat / 2.0) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2.0) ** 2
    return 6_371_008.8 * 2.0 * math.asin(min(1.0, math.sqrt(h)))


def _tag_truth(value: str | None) -> bool:
    if value is None:
        return False
    return str(value).strip().lower() not in {"", "no", "0", "false"}


def _parse_layer(value: str | None) -> int:
    try:
        layer = int(float(str(value))) if value is not None else 0
    except ValueError:
        return 0
    return max(-128, min(127, layer))


@dataclass(frozen=True)
class _PendingNode:
    osm_id: int
    lon: float
    lat: float


@dataclass(frozen=True)
class _PendingEdge:
    way_id: int
    segment_index: int
    source_osm: int
    target_osm: int
    length_m: float
    speed_kmh: float
    road_class: int
    access_class: AccessClass
    flags: int
    speed_source: SpeedSource
    layer: int
    access_reason: AccessReason


class GraphAccumulator:
    """Collect routing topology one OSM way at a time without retaining source ways."""

    def __init__(self) -> None:
        self._nodes: dict[int, _PendingNode] = {}
        self._edges: list[_PendingEdge] = []
        self.stats = GraphBuildStats()

    def add_way(self, way: WayInput) -> None:
        highway = str(way.tags.get("highway", "")).strip()
        if highway not in ROAD_CLASS:
            self.stats.skipped_way_count += 1
            return
        if len(way.node_ids) < 2 or len(way.node_ids) != len(way.coordinates):
            self.stats.skipped_way_count += 1
            return

        self.stats.way_count += 1
        oneway = parse_oneway(way.tags)
        access = classify_access(highway, way.tags)
        layer = _parse_layer(way.tags.get("layer"))
        base_flags = 0
        if _tag_truth(way.tags.get("bridge")):
            base_flags |= FLAG_BRIDGE
        if _tag_truth(way.tags.get("tunnel")):
            base_flags |= FLAG_TUNNEL

        for osm_id, (lon, lat) in zip(way.node_ids, way.coordinates):
            existing = self._nodes.get(int(osm_id))
            if existing is None:
                self._nodes[int(osm_id)] = _PendingNode(int(osm_id), float(lon), float(lat))

        for segment_index, ((source_id, source_coord), (target_id, target_coord)) in enumerate(
            zip(zip(way.node_ids, way.coordinates), zip(way.node_ids[1:], way.coordinates[1:]))
        ):
            if int(source_id) == int(target_id):
                continue
            length_m = geodesic_distance_m(source_coord, target_coord)
            if length_m <= 0.0:
                continue

            forward_speed = parse_maxspeed(way.tags.get("maxspeed:forward") or way.tags.get("maxspeed"), highway)
            backward_speed = parse_maxspeed(way.tags.get("maxspeed:backward") or way.tags.get("maxspeed"), highway)

            self._append_edge(
                way,
                segment_index,
                int(source_id),
                int(target_id),
                length_m,
                forward_speed,
                access,
                base_flags | (FLAG_AGAINST_ONEWAY if oneway == -1 else 0),
                layer,
            )
            self._append_edge(
                way,
                segment_index,
                int(target_id),
                int(source_id),
                length_m,
                backward_speed,
                access,
                base_flags | (FLAG_AGAINST_ONEWAY if oneway == 1 else 0),
                layer,
            )

    def _append_edge(
        self,
        way: WayInput,
        segment_index: int,
        source_osm: int,
        target_osm: int,
        length_m: float,
        speed: SpeedInfo,
        access: AccessInfo,
        flags: int,
        layer: int,
    ) -> None:
        highway = str(way.tags["highway"])
        self._edges.append(
            _PendingEdge(
                way_id=int(way.way_id),
                segment_index=segment_index,
                source_osm=source_osm,
                target_osm=target_osm,
                length_m=length_m,
                speed_kmh=speed.kmh,
                road_class=ROAD_CLASS[highway],
                access_class=access.access_class,
                flags=flags,
                speed_source=speed.source,
                layer=layer,
                access_reason=access.reason,
            )
        )
        if speed.source == SpeedSource.OSM:
            self.stats.explicit_speed_edges += 1
        else:
            self.stats.fallback_speed_edges += 1
            self.stats.fallback_by_highway[highway] += 1
            if speed.unknown_raw:
                self.stats.unknown_maxspeed[speed.unknown_raw] += 1
        if access.access_class != AccessClass.NORMAL:
            self.stats.restricted_edges += 1
        if flags & FLAG_AGAINST_ONEWAY:
            self.stats.against_oneway_edges += 1

    def finish(self) -> RoutingGraph:
        ordered_nodes = sorted(self._nodes.values(), key=lambda node: node.osm_id)
        node_index = {node.osm_id: index for index, node in enumerate(ordered_nodes)}
        ordered_edges = sorted(
            self._edges,
            key=lambda edge: (
                node_index[edge.source_osm],
                edge.way_id,
                edge.segment_index,
                node_index[edge.target_osm],
            ),
        )

        counts = [0] * len(ordered_nodes)
        for edge in ordered_edges:
            counts[node_index[edge.source_osm]] += 1

        offsets = [0] * len(ordered_nodes)
        running = 0
        for index, count in enumerate(counts):
            offsets[index] = running
            running += count

        nodes: list[GraphNode] = []
        for index, node in enumerate(ordered_nodes):
            x, y = project(node.lon, node.lat)
            nodes.append(
                GraphNode(
                    osm_id=node.osm_id,
                    lon=node.lon,
                    lat=node.lat,
                    x=x,
                    y=y,
                    adjacency_offset=offsets[index],
                    adjacency_count=counts[index],
                )
            )

        edges = tuple(
            GraphEdge(
                way_id=edge.way_id,
                segment_index=edge.segment_index,
                source_index=node_index[edge.source_osm],
                target_index=node_index[edge.target_osm],
                length_m=edge.length_m,
                speed_kmh=edge.speed_kmh,
                road_class=edge.road_class,
                access_class=edge.access_class,
                flags=edge.flags,
                speed_source=edge.speed_source,
                layer=edge.layer,
                access_reason=edge.access_reason,
            )
            for edge in ordered_edges
        )
        return RoutingGraph(tuple(nodes), edges)


def build_graph(ways: Iterable[WayInput]) -> tuple[RoutingGraph, GraphBuildStats]:
    accumulator = GraphAccumulator()
    for way in ways:
        accumulator.add_way(way)
    return accumulator.finish(), accumulator.stats


def write_brg1(graph: RoutingGraph, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as handle:
        handle.write(HEADER.pack(MAGIC, len(graph.nodes), len(graph.edges)))
        for node in graph.nodes:
            handle.write(
                NODE_RECORD.pack(
                    node.osm_id,
                    node.lon,
                    node.lat,
                    node.x,
                    node.y,
                    node.adjacency_offset,
                    node.adjacency_count,
                )
            )
        for edge in graph.edges:
            handle.write(
                EDGE_RECORD.pack(
                    edge.way_id,
                    edge.segment_index,
                    edge.source_index,
                    edge.target_index,
                    edge.length_m,
                    edge.speed_kmh,
                    edge.road_class,
                    int(edge.access_class),
                    edge.flags,
                    int(edge.speed_source),
                    edge.layer,
                    int(edge.access_reason),
                )
            )


def load_brg1(path: Path) -> RoutingGraph:
    with path.open("rb") as handle:
        header = handle.read(HEADER.size)
        if len(header) != HEADER.size:
            raise ValueError("BRG1 header is truncated")
        magic, node_count, edge_count = HEADER.unpack(header)
        if magic != MAGIC:
            raise ValueError(f"Unsupported routing graph magic: {magic!r}")

        nodes: list[GraphNode] = []
        for _ in range(node_count):
            raw = handle.read(NODE_RECORD.size)
            if len(raw) != NODE_RECORD.size:
                raise ValueError("BRG1 node table is truncated")
            osm_id, lon, lat, x, y, offset, count = NODE_RECORD.unpack(raw)
            nodes.append(GraphNode(osm_id, lon, lat, x, y, offset, count))

        edges: list[GraphEdge] = []
        for _ in range(edge_count):
            raw = handle.read(EDGE_RECORD.size)
            if len(raw) != EDGE_RECORD.size:
                raise ValueError("BRG1 edge table is truncated")
            (
                way_id,
                segment_index,
                source_index,
                target_index,
                length_m,
                speed_kmh,
                road_class,
                access_class,
                flags,
                speed_source,
                layer,
                access_reason,
            ) = EDGE_RECORD.unpack(raw)
            edges.append(
                GraphEdge(
                    way_id,
                    segment_index,
                    source_index,
                    target_index,
                    length_m,
                    speed_kmh,
                    road_class,
                    AccessClass(access_class),
                    flags,
                    SpeedSource(speed_source),
                    layer,
                    AccessReason(access_reason),
                )
            )

        if handle.read(1):
            raise ValueError("BRG1 contains unexpected trailing bytes")

    graph = RoutingGraph(tuple(nodes), tuple(edges))
    validate_graph(graph)
    return graph


def validate_graph(graph: RoutingGraph) -> None:
    node_count = len(graph.nodes)
    edge_count = len(graph.edges)
    expected_offset = 0
    for index, node in enumerate(graph.nodes):
        if node.adjacency_offset != expected_offset:
            raise ValueError(f"Invalid adjacency offset for node {index}")
        end = node.adjacency_offset + node.adjacency_count
        if end > edge_count:
            raise ValueError(f"Adjacency range outside edge table for node {index}")
        for edge in graph.edges[node.adjacency_offset:end]:
            if edge.source_index != index:
                raise ValueError(f"Adjacency table contains wrong source for node {index}")
        expected_offset = end
    if expected_offset != edge_count:
        raise ValueError("Adjacency ranges do not cover all edges")

    for edge in graph.edges:
        if not (0 <= edge.source_index < node_count and 0 <= edge.target_index < node_count):
            raise ValueError("Edge references an unknown node")
        if edge.length_m <= 0.0 or edge.speed_kmh <= 0.0:
            raise ValueError("Edge has non-positive length or speed")
        if edge.road_class not in ROAD_CLASS_NAME:
            raise ValueError("Edge has unknown road class")
