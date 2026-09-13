"""Build deterministic signalized-intersection movements and conflicts.

Dependencies:
- Consumes normalized BTS1 signal facts and the authoritative BRG1 routing graph.
- Pure Python domain/adapter logic; no Godot, rendering, UI, PBF parsing, or duplicate road graph.
"""

from __future__ import annotations

import math
from collections import deque
from dataclasses import dataclass
from typing import Iterable

from routing_graph import RoutingGraph, RoutingProfile, is_edge_allowed


@dataclass(frozen=True)
class StopPosition:
    x: float
    y: float
    source: str  # explicit | derived


@dataclass(frozen=True)
class Approach:
    id: str
    signal_id: str
    signal_osm_node_id: int
    way_ids: tuple[int, ...]
    x: float
    y: float
    direction_source: str
    relationship_source: str  # explicit | inferred | unresolved
    stop: StopPosition
    resolved: bool = True


@dataclass(frozen=True)
class Exit:
    id: str
    node_osm_id: int
    way_id: int
    x: float
    y: float


@dataclass(frozen=True)
class Movement:
    id: str
    approach_id: str
    exit_id: str
    resolved: bool


@dataclass(frozen=True)
class Intersection:
    id: str
    junction_osm_node_id: int
    junction_x: float
    junction_y: float
    approaches: tuple[Approach, ...]
    exits: tuple[Exit, ...]
    movements: tuple[Movement, ...]
    conflicts: tuple[tuple[str, str], ...]

    def conflicts_with(self, a: str, b: str) -> bool:
        return tuple(sorted((a, b))) in self.conflicts


@dataclass(frozen=True)
class BuildReport:
    intersections: tuple[Intersection, ...]
    unresolved_signal_ids: tuple[str, ...]

    @property
    def movement_count(self) -> int:
        return sum(len(item.movements) for item in self.intersections)

    @property
    def conflict_count(self) -> int:
        return sum(len(item.conflicts) for item in self.intersections)


def derive_stop_position(
    approach_xy: tuple[float, float],
    junction_xy: tuple[float, float],
    *,
    explicit_xy: tuple[float, float] | None = None,
    setback_m: float = 4.0,
) -> StopPosition:
    if explicit_xy is not None:
        return StopPosition(float(explicit_xy[0]), float(explicit_xy[1]), "explicit")
    ax, ay = approach_xy
    jx, jy = junction_xy
    dx = ax - jx
    dy = ay - jy
    length = math.hypot(dx, dy)
    if length <= 1e-6:
        return StopPosition(jx, jy, "derived")
    distance = min(max(0.0, setback_m), length)
    scale = distance / length
    return StopPosition(jx + dx * scale, jy + dy * scale, "derived")


def _orientation(a: tuple[float, float], b: tuple[float, float], c: tuple[float, float]) -> float:
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def _proper_intersection(
    a: tuple[float, float], b: tuple[float, float], c: tuple[float, float], d: tuple[float, float]
) -> bool:
    o1 = _orientation(a, b, c)
    o2 = _orientation(a, b, d)
    o3 = _orientation(c, d, a)
    o4 = _orientation(c, d, b)
    eps = 1e-7
    return ((o1 > eps and o2 < -eps) or (o1 < -eps and o2 > eps)) and (
        (o3 > eps and o4 < -eps) or (o3 < -eps and o4 > eps)
    )


def _unit_from_junction(point: tuple[float, float], junction: tuple[float, float]) -> tuple[float, float]:
    dx = point[0] - junction[0]
    dy = point[1] - junction[1]
    length = math.hypot(dx, dy)
    if length <= 1e-6:
        return (0.0, 0.0)
    return (dx / length, dy / length)


def _same_direction(a: tuple[float, float], b: tuple[float, float], threshold: float = 0.985) -> bool:
    return a[0] * b[0] + a[1] * b[1] >= threshold


def _opposite_direction(a: tuple[float, float], b: tuple[float, float], threshold: float = -0.985) -> bool:
    return a[0] * b[0] + a[1] * b[1] <= threshold


def build_intersection(
    intersection_id: str,
    junction_osm_node_id: int,
    junction_xy: tuple[float, float],
    approaches: Iterable[Approach],
    exits: Iterable[Exit],
) -> Intersection:
    ordered_approaches = tuple(sorted(approaches, key=lambda item: item.id))
    ordered_exits = tuple(sorted(exits, key=lambda item: item.id))
    movement_rows: list[Movement] = []
    movement_geometry: dict[str, tuple[tuple[float, float], tuple[float, float]]] = {}

    for approach in ordered_approaches:
        approach_dir = _unit_from_junction((approach.x, approach.y), junction_xy)
        for exit_row in ordered_exits:
            exit_dir = _unit_from_junction((exit_row.x, exit_row.y), junction_xy)
            if _same_direction(approach_dir, exit_dir):
                continue
            movement_id = f"{approach.id}->{exit_row.id}"
            resolved = approach.resolved and approach_dir != (0.0, 0.0) and exit_dir != (0.0, 0.0)
            movement_rows.append(Movement(movement_id, approach.id, exit_row.id, resolved))
            movement_geometry[movement_id] = ((approach.stop.x, approach.stop.y), (exit_row.x, exit_row.y))

    movements = tuple(sorted(movement_rows, key=lambda item: item.id))
    approach_by_id = {item.id: item for item in ordered_approaches}
    exit_by_id = {item.id: item for item in ordered_exits}
    conflicts: set[tuple[str, str]] = set()

    for index, left in enumerate(movements):
        for right in movements[index + 1 :]:
            if not left.resolved or not right.resolved:
                conflict = True
            elif left.approach_id == right.approach_id or left.exit_id == right.exit_id:
                conflict = True
            else:
                la = approach_by_id[left.approach_id]
                ra = approach_by_id[right.approach_id]
                le = exit_by_id[left.exit_id]
                re = exit_by_id[right.exit_id]
                la_dir = _unit_from_junction((la.x, la.y), junction_xy)
                ra_dir = _unit_from_junction((ra.x, ra.y), junction_xy)
                le_dir = _unit_from_junction((le.x, le.y), junction_xy)
                re_dir = _unit_from_junction((re.x, re.y), junction_xy)
                opposing_straights = (
                    _opposite_direction(la_dir, ra_dir)
                    and _opposite_direction(la_dir, le_dir)
                    and _opposite_direction(ra_dir, re_dir)
                )
                conflict = False
                if not opposing_straights:
                    l0, l1 = movement_geometry[left.id]
                    r0, r1 = movement_geometry[right.id]
                    conflict = _proper_intersection(l0, l1, r0, r1)
                    if not conflict:
                        l_cross = _orientation(junction_xy, l0, l1)
                        r_cross = _orientation(junction_xy, r0, r1)
                        conflict = abs(l_cross) > 1e-6 and abs(r_cross) > 1e-6 and (l_cross > 0) != (r_cross > 0)
            if conflict:
                conflicts.add(tuple(sorted((left.id, right.id))))

    return Intersection(
        intersection_id,
        junction_osm_node_id,
        float(junction_xy[0]),
        float(junction_xy[1]),
        ordered_approaches,
        ordered_exits,
        movements,
        tuple(sorted(conflicts)),
    )


class _TopologyIndex:
    def __init__(self, graph: RoutingGraph) -> None:
        self.graph = graph
        self.node_by_osm = {node.osm_id: index for index, node in enumerate(graph.nodes)}
        self.neighbors: dict[int, list[tuple[int, int]]] = {index: [] for index in range(len(graph.nodes))}
        self.incident_ways: dict[int, set[int]] = {index: set() for index in range(len(graph.nodes))}
        self.outgoing: dict[int, list] = {index: [] for index in range(len(graph.nodes))}
        seen: set[tuple[int, int, int]] = set()
        for edge in graph.edges:
            self.incident_ways[edge.source_index].add(edge.way_id)
            self.incident_ways[edge.target_index].add(edge.way_id)
            if is_edge_allowed(edge, RoutingProfile.NORMAL):
                self.outgoing[edge.source_index].append(edge)
            key = (min(edge.source_index, edge.target_index), max(edge.source_index, edge.target_index), edge.way_id)
            if key not in seen:
                self.neighbors[edge.source_index].append((edge.target_index, edge.way_id))
                self.neighbors[edge.target_index].append((edge.source_index, edge.way_id))
                seen.add(key)
        for rows in self.neighbors.values():
            rows.sort(key=lambda row: (graph.nodes[row[0]].osm_id, row[1]))
        for rows in self.outgoing.values():
            rows.sort(key=lambda edge: (edge.way_id, graph.nodes[edge.target_index].osm_id, edge.segment_index))

    def nearest_junction(self, signal_osm: int, way_ids: tuple[int, ...], max_hops: int = 16) -> int | None:
        start = self.node_by_osm.get(signal_osm)
        if start is None:
            return None
        allowed = set(way_ids)
        if len(self.incident_ways[start]) >= 2:
            return start
        frontier = deque([(start, 0)])
        visited = {start}
        candidates: list[tuple[int, int]] = []
        while frontier:
            node_index, hops = frontier.popleft()
            if hops >= max_hops:
                continue
            for neighbor, way_id in self.neighbors[node_index]:
                if allowed and way_id not in allowed:
                    continue
                if neighbor in visited:
                    continue
                visited.add(neighbor)
                next_hops = hops + 1
                if len(self.incident_ways[neighbor]) >= 2:
                    candidates.append((next_hops, neighbor))
                else:
                    frontier.append((neighbor, next_hops))
        if not candidates:
            return None
        candidates.sort(key=lambda item: (item[0], graph_node_id(self.graph, item[1])))
        return candidates[0][1]

    def outward_point(self, signal_index: int, junction_index: int, way_ids: tuple[int, ...]) -> tuple[float, float]:
        signal = self.graph.nodes[signal_index]
        junction = self.graph.nodes[junction_index]
        if signal_index != junction_index and math.hypot(signal.x - junction.x, signal.y - junction.y) > 1.0:
            return (signal.x, signal.y)
        allowed = set(way_ids)
        options = [self.graph.nodes[neighbor] for neighbor, way_id in self.neighbors[junction_index] if not allowed or way_id in allowed]
        if not options:
            return (signal.x, signal.y)
        options.sort(key=lambda node: (-math.hypot(node.x - junction.x, node.y - junction.y), node.osm_id))
        return (options[0].x, options[0].y)

    def exits(self, junction_index: int) -> tuple[Exit, ...]:
        rows: dict[tuple[int, int], Exit] = {}
        for edge in self.outgoing[junction_index]:
            target = self.graph.nodes[edge.target_index]
            key = (edge.target_index, edge.way_id)
            rows[key] = Exit(f"w{edge.way_id}:n{target.osm_id}", target.osm_id, edge.way_id, target.x, target.y)
        return tuple(sorted(rows.values(), key=lambda item: item.id))


def graph_node_id(graph: RoutingGraph, index: int) -> int:
    return graph.nodes[index].osm_id


def _relationship_source(direction_source: str, way_ids: tuple[int, ...], approach_xy: tuple[float, float], junction_xy: tuple[float, float]) -> str:
    if direction_source in {"explicit", "legacy", "inferred"}:
        return "explicit" if direction_source in {"explicit", "legacy"} else "inferred"
    if len(way_ids) == 1 and math.hypot(approach_xy[0] - junction_xy[0], approach_xy[1] - junction_xy[1]) > 1.0:
        return "inferred"
    return "unresolved"


def build_from_runtime_data(signal_dataset: dict, graph: RoutingGraph, *, max_hops: int = 16) -> BuildReport:
    if signal_dataset.get("format") != "BTS1":
        raise ValueError("traffic intersection builder requires BTS1 signal data")
    signals = signal_dataset.get("signals")
    if not isinstance(signals, list):
        raise ValueError("BTS1 dataset is missing signals")

    topology = _TopologyIndex(graph)
    grouped: dict[int, list[dict]] = {}
    unresolved: list[str] = []
    for value in signals:
        if not isinstance(value, dict):
            continue
        signal_id = str(value.get("id", ""))
        try:
            osm_node_id = int(value["osm_node_id"])
            way_ids = tuple(sorted({int(item) for item in value.get("highway_way_ids", [])}))
        except (KeyError, TypeError, ValueError):
            unresolved.append(signal_id or "<unknown>")
            continue
        junction_index = topology.nearest_junction(osm_node_id, way_ids, max_hops=max_hops)
        if junction_index is None:
            unresolved.append(signal_id)
            continue
        grouped.setdefault(junction_index, []).append(value)

    intersections: list[Intersection] = []
    for junction_index, group in sorted(grouped.items(), key=lambda item: graph.nodes[item[0]].osm_id):
        junction = graph.nodes[junction_index]
        junction_xy = (junction.x, junction.y)
        approaches: list[Approach] = []
        for signal in sorted(group, key=lambda item: str(item.get("id", ""))):
            signal_osm = int(signal["osm_node_id"])
            signal_index = topology.node_by_osm.get(signal_osm)
            if signal_index is None:
                unresolved.append(str(signal.get("id", "")))
                continue
            way_ids = tuple(sorted({int(item) for item in signal.get("highway_way_ids", [])}))
            approach_xy = topology.outward_point(signal_index, junction_index, way_ids)
            explicit = bool(signal.get("explicit_stop_line"))
            explicit_xy = (float(signal["x"]), float(signal["y"])) if explicit else None
            stop = derive_stop_position(approach_xy, junction_xy, explicit_xy=explicit_xy)
            direction_source = str(signal.get("direction_source", "unknown"))
            relationship_source = _relationship_source(direction_source, way_ids, approach_xy, junction_xy)
            approaches.append(
                Approach(
                    id=f"approach:{signal['id']}",
                    signal_id=str(signal["id"]),
                    signal_osm_node_id=signal_osm,
                    way_ids=way_ids,
                    x=float(approach_xy[0]),
                    y=float(approach_xy[1]),
                    direction_source=direction_source,
                    relationship_source=relationship_source,
                    stop=stop,
                    resolved=relationship_source != "unresolved",
                )
            )
        exits = topology.exits(junction_index)
        if not approaches or not exits:
            unresolved.extend(item.signal_id for item in approaches)
            continue
        intersections.append(build_intersection(f"junction-node:{junction.osm_id}", junction.osm_id, junction_xy, approaches, exits))

    return BuildReport(tuple(intersections), tuple(sorted(set(unresolved))))
