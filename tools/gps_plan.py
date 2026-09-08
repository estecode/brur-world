"""Own ordered GPS stops and route-leg reuse without owning UI state.

Dependencies:
- gps_routing.py performs snapping and path search.
- This module only stores ordered waypoints/destination and cached leg results.
"""

from __future__ import annotations

from dataclasses import dataclass

from gps_routing import EdgeCostPolicy, GraphRouter, RoadSnap, RouteResult


@dataclass(frozen=True)
class RouteTarget:
    target_id: str
    display_name: str
    snap: RoadSnap


@dataclass(frozen=True)
class RouteLeg:
    from_id: str
    to_id: str
    result: RouteResult


@dataclass(frozen=True)
class RoutePlanResult:
    success: bool
    legs: tuple[RouteLeg, ...]
    failed_leg_index: int | None = None
    failure_reason: str | None = None


class RoutePlan:
    """Ordered waypoints plus one distinct destination.

    Leg caching is keyed by the actual snapped endpoints and routing policy, so
    removing or inserting a waypoint only recalculates legs whose endpoints changed.
    """

    def __init__(self) -> None:
        self._waypoints: list[RouteTarget] = []
        self._destination: RouteTarget | None = None
        self._leg_cache: dict[tuple[RoadSnap, RoadSnap, EdgeCostPolicy, int], RouteResult] = {}

    @property
    def waypoints(self) -> tuple[RouteTarget, ...]:
        return tuple(self._waypoints)

    @property
    def destination(self) -> RouteTarget | None:
        return self._destination

    def set_destination(self, target: RouteTarget | None) -> None:
        self._destination = target

    def add_waypoint(self, target: RouteTarget, index: int | None = None) -> None:
        if index is None:
            self._waypoints.append(target)
            return
        if not 0 <= index <= len(self._waypoints):
            raise IndexError("waypoint index out of range")
        self._waypoints.insert(index, target)

    def remove_waypoint(self, index: int) -> RouteTarget:
        return self._waypoints.pop(index)

    def clear_waypoints(self) -> None:
        self._waypoints.clear()

    def ordered_targets(self) -> tuple[RouteTarget, ...]:
        if self._destination is None:
            return tuple(self._waypoints)
        return tuple(self._waypoints) + (self._destination,)

    def recalculate(
        self,
        start: RoadSnap,
        router: GraphRouter,
        policy: EdgeCostPolicy,
        start_id: str = "start",
    ) -> RoutePlanResult:
        targets = self.ordered_targets()
        if not targets:
            return RoutePlanResult(False, (), 0, "no_destination")
        if self._destination is None:
            return RoutePlanResult(False, (), len(targets), "no_destination")

        legs: list[RouteLeg] = []
        from_snap = start
        from_id = start_id
        for leg_index, target in enumerate(targets):
            key = (from_snap, target.snap, policy, int(router.profile))
            result = self._leg_cache.get(key)
            if result is None:
                result = router.route_snaps(from_snap, target.snap, policy)
                self._leg_cache[key] = result
            leg = RouteLeg(from_id, target.target_id, result)
            legs.append(leg)
            if not result.success:
                return RoutePlanResult(False, tuple(legs), leg_index, result.failure_reason)
            from_snap = target.snap
            from_id = target.target_id

        return RoutePlanResult(True, tuple(legs))
