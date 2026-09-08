"""Build a topology-compressed routing graph from decoded OSM ways.

Dependencies:
- Uses routing_graph.py for routing policy/data types and BRG1 record definitions.
- Used only by the offline routing compiler; Godot/runtime still consumes BRG1.

Shape nodes that only describe road geometry are not routing nodes. Ways are split at
endpoints, shared OSM nodes and the extra breakpoint needed to preserve closed ways.
Metric length is accumulated over every original OSM segment between breakpoints.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable

from routing_graph import (
    EDGE_RECORD,
    HEADER,
    MAGIC,
    NODE_RECORD,
    FLAG_AGAINST_ONEWAY,
    FLAG_BRIDGE,
    FLAG_TUNNEL,
    ROAD_CLASS,
    AccessClass,
    GraphBuildStats,
    GraphEdge,
    GraphNode,
    RoutingGraph,
    SpeedInfo,
    SpeedSource,
    WayInput,
    classify_access,
    geodesic_distance_m,
    parse_maxspeed,
    parse_oneway,
)
from world_common import project


ProgressCallback = Callable[[str, int, str], None]


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


def _is_routable_shape(node_ids: Iterable[int], highway: str) -> bool:
    if highway not in ROAD_CLASS:
        return False
    try:
        return len(node_ids) >= 2  # type: ignore[arg-type]
    except TypeError:
        return len(tuple(node_ids)) >= 2


class BreakpointIndex:
    """Find OSM nodes where a routing way must be split without storing source ways."""

    def __init__(self) -> None:
        self._seen_nodes: set[int] = set()
        self.breakpoints: set[int] = set()
        self.routable_way_count = 0
        self.skipped_way_count = 0

    def observe_way(self, node_ids: list[int], highway: str) -> bool:
        if highway not in ROAD_CLASS or len(node_ids) < 2:
            self.skipped_way_count += 1
            return False

        self.routable_way_count += 1
        ids = [int(node_id) for node_id in node_ids]
        self.breakpoints.add(ids[0])
        self.breakpoints.add(ids[-1])

        # A closed way with no external junction still needs two distinct graph nodes,
        # otherwise the complete loop would collapse into an unusable self-edge.
        if len(ids) > 2 and ids[0] == ids[-1]:
            self.breakpoints.add(ids[len(ids) // 2])

        for node_id in ids:
            if node_id in self._seen_nodes:
                self.breakpoints.add(node_id)
            else:
                self._seen_nodes.add(node_id)
        return True

    @property
    def seen_node_count(self) -> int:
        return len(self._seen_nodes)

    def release_seen_nodes(self) -> None:
        """Free the large pass-1 uniqueness set before graph materialization."""
        self._seen_nodes.clear()


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
    access_class: int
    flags: int
    speed_source: int
    layer: int
    access_reason: int


class CompressedGraphAccumulator:
    """Emit edges only between routing breakpoints while retaining true way length."""

    def __init__(self, breakpoints: set[int]) -> None:
        self.breakpoints = breakpoints
        self._nodes: dict[int, _PendingNode] = {}
        self._edges: list[_PendingEdge] = []
        self.stats = GraphBuildStats()
        self.original_shape_segments = 0

    @property
    def pending_node_count(self) -> int:
        return len(self._nodes)

    @property
    def pending_edge_count(self) -> int:
        return len(self._edges)

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
        flags = 0
        if _tag_truth(way.tags.get("bridge")):
            flags |= FLAG_BRIDGE
        if _tag_truth(way.tags.get("tunnel")):
            flags |= FLAG_TUNNEL

        # Parse once per OSM way, not once per shape segment.
        forward_speed = parse_maxspeed(way.tags.get("maxspeed:forward") or way.tags.get("maxspeed"), highway)
        backward_speed = parse_maxspeed(way.tags.get("maxspeed:backward") or way.tags.get("maxspeed"), highway)

        start_index = 0
        accumulated_length = 0.0
        for index in range(1, len(way.node_ids)):
            source_coord = way.coordinates[index - 1]
            target_coord = way.coordinates[index]
            self.original_shape_segments += 1
            if int(way.node_ids[index - 1]) != int(way.node_ids[index]):
                accumulated_length += geodesic_distance_m(source_coord, target_coord)

            target_id = int(way.node_ids[index])
            if index != len(way.node_ids) - 1 and target_id not in self.breakpoints:
                continue

            source_id = int(way.node_ids[start_index])
            if accumulated_length > 0.0:
                self._remember_node(source_id, way.coordinates[start_index])
                self._remember_node(target_id, way.coordinates[index])
                self._append_edge(
                    way,
                    start_index,
                    source_id,
                    target_id,
                    accumulated_length,
                    forward_speed,
                    access.access_class,
                    access.reason,
                    flags | (FLAG_AGAINST_ONEWAY if oneway == -1 else 0),
                    layer,
                )
                self._append_edge(
                    way,
                    start_index,
                    target_id,
                    source_id,
                    accumulated_length,
                    backward_speed,
                    access.access_class,
                    access.reason,
                    flags | (FLAG_AGAINST_ONEWAY if oneway == 1 else 0),
                    layer,
                )

            start_index = index
            accumulated_length = 0.0

    def _remember_node(self, osm_id: int, coord: tuple[float, float]) -> None:
        if osm_id not in self._nodes:
            self._nodes[osm_id] = _PendingNode(osm_id, float(coord[0]), float(coord[1]))

    def _append_edge(
        self,
        way: WayInput,
        segment_index: int,
        source_osm: int,
        target_osm: int,
        length_m: float,
        speed: SpeedInfo,
        access_class: AccessClass,
        access_reason: int,
        flags: int,
        layer: int,
    ) -> None:
        highway = str(way.tags["highway"])
        self._edges.append(
            _PendingEdge(
                way_id=int(way.way_id),
                segment_index=int(segment_index),
                source_osm=source_osm,
                target_osm=target_osm,
                length_m=length_m,
                speed_kmh=speed.kmh,
                road_class=ROAD_CLASS[highway],
                access_class=int(access_class),
                flags=flags,
                speed_source=int(speed.source),
                layer=layer,
                access_reason=int(access_reason),
            )
        )
        if speed.source == SpeedSource.OSM:
            self.stats.explicit_speed_edges += 1
        else:
            self.stats.fallback_speed_edges += 1
            self.stats.fallback_by_highway[highway] += 1
            if speed.unknown_raw:
                self.stats.unknown_maxspeed[speed.unknown_raw] += 1
        if access_class != AccessClass.NORMAL:
            self.stats.restricted_edges += 1
        if flags & FLAG_AGAINST_ONEWAY:
            self.stats.against_oneway_edges += 1

    def finish(self, progress: ProgressCallback | None = None) -> RoutingGraph:
        ordered_nodes = sorted(self._nodes.values(), key=lambda node: node.osm_id)
        node_index = {node.osm_id: index for index, node in enumerate(ordered_nodes)}

        counts = [0] * len(ordered_nodes)
        for processed, edge in enumerate(self._edges, start=1):
            counts[node_index[edge.source_osm]] += 1
            if progress and processed % 100_000 == 0:
                progress("counting adjacency", processed, f"{len(self._edges):,} edges total")

        offsets = [0] * len(ordered_nodes)
        running = 0
        for index, count in enumerate(counts):
            offsets[index] = running
            running += count
            if progress and (index + 1) % 100_000 == 0:
                progress("building offsets", index + 1, f"{len(ordered_nodes):,} nodes total")

        # Linear-time adjacency grouping replaces the previous global O(E log E) edge sort.
        positions = offsets.copy()
        grouped: list[_PendingEdge | None] = [None] * len(self._edges)
        for processed, edge in enumerate(self._edges, start=1):
            source_index = node_index[edge.source_osm]
            position = positions[source_index]
            grouped[position] = edge
            positions[source_index] += 1
            if progress and processed % 100_000 == 0:
                progress("grouping adjacency", processed, f"{len(self._edges):,} edges total")

        nodes: list[GraphNode] = []
        for index, node in enumerate(ordered_nodes):
            x, y = project(node.lon, node.lat)
            nodes.append(GraphNode(node.osm_id, node.lon, node.lat, x, y, offsets[index], counts[index]))
            if progress and (index + 1) % 100_000 == 0:
                progress("projecting nodes", index + 1, f"{len(ordered_nodes):,} nodes total")

        edges: list[GraphEdge] = []
        for processed, pending in enumerate(grouped, start=1):
            if pending is None:
                raise RuntimeError("Internal routing adjacency grouping hole")
            edges.append(
                GraphEdge(
                    pending.way_id,
                    pending.segment_index,
                    node_index[pending.source_osm],
                    node_index[pending.target_osm],
                    pending.length_m,
                    pending.speed_kmh,
                    pending.road_class,
                    AccessClass(pending.access_class),
                    pending.flags,
                    SpeedSource(pending.speed_source),
                    pending.layer,
                    pending.access_reason,
                )
            )
            if progress and processed % 100_000 == 0:
                progress("materializing edges", processed, f"{len(grouped):,} edges total")

        return RoutingGraph(tuple(nodes), tuple(edges))


def build_compressed_graph(ways: Iterable[WayInput]) -> tuple[RoutingGraph, GraphBuildStats]:
    """Small-fixture helper that runs the same two-pass topology used by production."""
    source = list(ways)
    topology = BreakpointIndex()
    for way in source:
        topology.observe_way(list(way.node_ids), str(way.tags.get("highway", "")).strip())
    topology.release_seen_nodes()

    accumulator = CompressedGraphAccumulator(topology.breakpoints)
    for way in source:
        accumulator.add_way(way)
    return accumulator.finish(), accumulator.stats


def write_brg1_with_progress(
    graph: RoutingGraph,
    path: Path,
    progress: ProgressCallback | None = None,
) -> None:
    """Write BRG1 while exposing progress for multi-minute country builds."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as handle:
        handle.write(HEADER.pack(MAGIC, len(graph.nodes), len(graph.edges)))
        for processed, node in enumerate(graph.nodes, start=1):
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
            if progress and processed % 100_000 == 0:
                progress("writing nodes", processed, f"{len(graph.nodes):,} nodes total")

        for processed, edge in enumerate(graph.edges, start=1):
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
            if progress and processed % 100_000 == 0:
                progress("writing edges", processed, f"{len(graph.edges):,} edges total")
