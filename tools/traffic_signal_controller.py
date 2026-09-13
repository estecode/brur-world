"""Drive deterministic traffic-signal phases from the intersection conflict model.

Dependencies:
- Consumes immutable Intersection/Movement data from traffic_intersections.
- Pure traffic/domain logic; no Godot, rendering, UI, SceneTree, WorldClock, or PBF access.

Swedish vehicle signal semantics use RED -> RED_YELLOW -> GREEN -> YELLOW -> RED.
The state order and stop/go meaning follow current Swedish traffic-signal definitions;
the default durations below are gameplay approximations and remain explicit policy data.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from traffic_intersections import Intersection


class SignalState(str, Enum):
    RED = "red"
    RED_YELLOW = "red_yellow"
    GREEN = "green"
    YELLOW = "yellow"


class ControllerStage(str, Enum):
    ALL_RED = "all_red"
    RED_YELLOW = "red_yellow"
    GREEN = "green"
    YELLOW = "yellow"


@dataclass(frozen=True)
class TimingPolicy:
    """Configurable gameplay timings, in seconds, for one vehicle phase."""

    red_yellow_s: float = 1.0
    green_s: float = 12.0
    yellow_s: float = 3.0
    clearance_s: float = 1.0

    def __post_init__(self) -> None:
        values = (self.red_yellow_s, self.green_s, self.yellow_s, self.clearance_s)
        if any(value <= 0.0 for value in values):
            raise ValueError("traffic signal durations must be > 0")


@dataclass(frozen=True)
class SignalPhase:
    movement_ids: tuple[str, ...]


@dataclass(frozen=True)
class ControllerSnapshot:
    phase_index: int
    stage: ControllerStage
    elapsed_s: float


def build_phase_plan(intersection: Intersection) -> tuple[SignalPhase, ...]:
    """Partition resolved movements into deterministic conflict-free phases.

    The greedy order is deliberately stable and small: movement ids are sorted, then
    each phase accepts every remaining movement compatible with everything already
    selected for that phase. Unresolved movements are never released.
    """

    ordered = tuple(sorted(movement.id for movement in intersection.movements if movement.resolved))
    remaining = set(ordered)
    phases: list[SignalPhase] = []

    while remaining:
        selected: list[str] = []
        for movement_id in ordered:
            if movement_id not in remaining:
                continue
            if all(not intersection.conflicts_with(movement_id, current) for current in selected):
                selected.append(movement_id)
        if not selected:
            raise ValueError("resolved traffic movements could not be assigned to a phase")
        phases.append(SignalPhase(tuple(selected)))
        remaining.difference_update(selected)

    return tuple(phases)


class IntersectionSignalController:
    """Cycle one intersection through deterministic, conflict-safe signal phases."""

    _EPSILON = 1e-9

    def __init__(self, intersection: Intersection, timing: TimingPolicy | None = None) -> None:
        self.intersection = intersection
        self.timing = timing or TimingPolicy()
        self.phases = build_phase_plan(intersection)
        self._movement_ids = {movement.id for movement in intersection.movements}
        self.reset()

    @property
    def phase_index(self) -> int:
        return self._phase_index

    @property
    def stage(self) -> ControllerStage:
        return self._stage

    @property
    def elapsed_s(self) -> float:
        return self._elapsed_s

    @property
    def active_movement_ids(self) -> tuple[str, ...]:
        if not self.phases or self._stage == ControllerStage.ALL_RED:
            return ()
        return self.phases[self._phase_index].movement_ids

    def reset(self) -> None:
        self._phase_index = 0
        self._stage = ControllerStage.ALL_RED
        self._elapsed_s = 0.0

    def snapshot(self) -> ControllerSnapshot:
        return ControllerSnapshot(self._phase_index, self._stage, self._elapsed_s)

    def restore(self, snapshot: ControllerSnapshot) -> None:
        if snapshot.elapsed_s < 0.0:
            raise ValueError("controller snapshot elapsed time must be >= 0")
        if not self.phases:
            if snapshot.phase_index != 0 or snapshot.stage != ControllerStage.ALL_RED:
                raise ValueError("empty intersection controller can only restore safe all-red state")
        elif snapshot.phase_index < 0 or snapshot.phase_index >= len(self.phases):
            raise ValueError("controller snapshot phase index is out of range")
        duration = self._duration_for(snapshot.stage)
        if snapshot.elapsed_s >= duration:
            raise ValueError("controller snapshot elapsed time must be inside its current stage")
        self._phase_index = snapshot.phase_index
        self._stage = snapshot.stage
        self._elapsed_s = float(snapshot.elapsed_s)

    def state_for_movement(self, movement_id: str) -> SignalState:
        if movement_id not in self._movement_ids:
            raise KeyError(f"unknown movement: {movement_id}")
        if not self.phases or self._stage == ControllerStage.ALL_RED:
            return SignalState.RED
        if movement_id not in self.phases[self._phase_index].movement_ids:
            return SignalState.RED
        if self._stage == ControllerStage.RED_YELLOW:
            return SignalState.RED_YELLOW
        if self._stage == ControllerStage.GREEN:
            return SignalState.GREEN
        if self._stage == ControllerStage.YELLOW:
            return SignalState.YELLOW
        return SignalState.RED

    def movement_permitted(self, movement_id: str) -> bool:
        """Return whether a not-yet-committed vehicle may enter this movement."""

        return self.state_for_movement(movement_id) == SignalState.GREEN

    def tick(self, dt_s: float) -> None:
        if dt_s < 0.0:
            raise ValueError("traffic signal dt must be >= 0")
        if dt_s == 0.0 or not self.phases:
            return

        remaining = float(dt_s)
        while remaining > self._EPSILON:
            duration = self._duration_for(self._stage)
            to_boundary = duration - self._elapsed_s
            if remaining + self._EPSILON < to_boundary:
                self._elapsed_s += remaining
                return
            remaining = max(0.0, remaining - to_boundary)
            self._elapsed_s = 0.0
            self._advance_stage()

    def _duration_for(self, stage: ControllerStage) -> float:
        if stage == ControllerStage.ALL_RED:
            return self.timing.clearance_s
        if stage == ControllerStage.RED_YELLOW:
            return self.timing.red_yellow_s
        if stage == ControllerStage.GREEN:
            return self.timing.green_s
        if stage == ControllerStage.YELLOW:
            return self.timing.yellow_s
        raise ValueError(f"unsupported controller stage: {stage}")

    def _advance_stage(self) -> None:
        if self._stage == ControllerStage.ALL_RED:
            self._stage = ControllerStage.RED_YELLOW
        elif self._stage == ControllerStage.RED_YELLOW:
            self._stage = ControllerStage.GREEN
        elif self._stage == ControllerStage.GREEN:
            self._stage = ControllerStage.YELLOW
        else:
            self._stage = ControllerStage.ALL_RED
            self._phase_index = (self._phase_index + 1) % len(self.phases)
