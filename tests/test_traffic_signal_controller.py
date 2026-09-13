"""Tests deterministic conflict-safe traffic signal phase control.

Dependencies:
- Uses production traffic_intersections and traffic_signal_controller domain modules.
- Uses only tiny deterministic fixtures; no Godot, rendering, UI, or PBF input.
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from traffic_intersections import Approach, Exit, StopPosition, build_intersection
from traffic_signal_controller import (
    ControllerSnapshot,
    ControllerStage,
    IntersectionSignalController,
    SignalState,
    TimingPolicy,
    build_phase_plan,
)


def approach(name: str, x: float, y: float, *, resolved: bool = True) -> Approach:
    return Approach(
        name,
        name,
        int(name.split(":")[-1]),
        (),
        x,
        y,
        "explicit",
        "explicit" if resolved else "unresolved",
        StopPosition(x, y, "explicit"),
        resolved,
    )


def exit_row(name: str, osm: int, way: int, x: float, y: float) -> Exit:
    return Exit(name, osm, way, x, y)


def four_way():
    return build_intersection(
        "cross",
        1,
        (0.0, 0.0),
        [
            approach("a:1", 0.0, -10.0),
            approach("a:2", 0.0, 10.0),
            approach("a:3", -10.0, 0.0),
            approach("a:4", 10.0, 0.0),
        ],
        [
            exit_row("e:north", 11, 101, 0.0, -10.0),
            exit_row("e:south", 12, 102, 0.0, 10.0),
            exit_row("e:west", 13, 103, -10.0, 0.0),
            exit_row("e:east", 14, 104, 10.0, 0.0),
        ],
    )


def t_junction():
    return build_intersection(
        "tee",
        2,
        (0.0, 0.0),
        [
            approach("a:1", 0.0, 10.0),
            approach("a:2", -10.0, 0.0),
            approach("a:3", 10.0, 0.0),
        ],
        [
            exit_row("e:north", 21, 201, 0.0, 10.0),
            exit_row("e:west", 22, 202, -10.0, 0.0),
            exit_row("e:east", 23, 203, 10.0, 0.0),
        ],
    )


class TrafficSignalControllerTests(unittest.TestCase):
    def test_phase_plan_is_deterministic_and_conflict_free(self) -> None:
        intersection = four_way()
        first = build_phase_plan(intersection)
        second = build_phase_plan(intersection)
        self.assertEqual(first, second)
        self.assertGreaterEqual(len(first), 2)
        assigned = []
        for phase in first:
            assigned.extend(phase.movement_ids)
            for index, left in enumerate(phase.movement_ids):
                for right in phase.movement_ids[index + 1 :]:
                    self.assertFalse(intersection.conflicts_with(left, right))
        self.assertEqual(
            sorted(assigned),
            sorted(movement.id for movement in intersection.movements if movement.resolved),
        )

    def test_t_junction_plan_is_conflict_free(self) -> None:
        intersection = t_junction()
        phases = build_phase_plan(intersection)
        self.assertTrue(phases)
        for phase in phases:
            for index, left in enumerate(phase.movement_ids):
                for right in phase.movement_ids[index + 1 :]:
                    self.assertFalse(intersection.conflicts_with(left, right))

    def test_swedish_signal_order_and_configured_durations(self) -> None:
        intersection = four_way()
        timing = TimingPolicy(clearance_s=2.0, red_yellow_s=1.0, green_s=4.0, yellow_s=1.5)
        controller = IntersectionSignalController(intersection, timing)
        movement = controller.phases[0].movement_ids[0]

        self.assertEqual(controller.state_for_movement(movement), SignalState.RED)
        self.assertFalse(controller.movement_permitted(movement))
        controller.tick(2.0)
        self.assertEqual(controller.state_for_movement(movement), SignalState.RED_YELLOW)
        self.assertFalse(controller.movement_permitted(movement))
        controller.tick(1.0)
        self.assertEqual(controller.state_for_movement(movement), SignalState.GREEN)
        self.assertTrue(controller.movement_permitted(movement))
        controller.tick(4.0)
        self.assertEqual(controller.state_for_movement(movement), SignalState.YELLOW)
        self.assertFalse(controller.movement_permitted(movement))
        controller.tick(1.5)
        self.assertEqual(controller.state_for_movement(movement), SignalState.RED)
        self.assertEqual(controller.stage, ControllerStage.ALL_RED)

    def test_no_conflicting_movements_are_ever_permitted(self) -> None:
        intersection = four_way()
        controller = IntersectionSignalController(
            intersection,
            TimingPolicy(clearance_s=0.5, red_yellow_s=0.5, green_s=1.0, yellow_s=0.5),
        )
        ids = tuple(movement.id for movement in intersection.movements)
        for _ in range(80):
            permitted = [movement_id for movement_id in ids if controller.movement_permitted(movement_id)]
            for index, left in enumerate(permitted):
                for right in permitted[index + 1 :]:
                    self.assertFalse(intersection.conflicts_with(left, right))
            controller.tick(0.25)

    def test_unresolved_movement_stays_red(self) -> None:
        intersection = build_intersection(
            "unresolved",
            3,
            (0.0, 0.0),
            [approach("a:1", 0.0, -10.0, resolved=False), approach("a:2", 0.0, 10.0)],
            [exit_row("e:west", 31, 301, -10.0, 0.0), exit_row("e:east", 32, 302, 10.0, 0.0)],
        )
        controller = IntersectionSignalController(
            intersection,
            TimingPolicy(clearance_s=0.5, red_yellow_s=0.5, green_s=1.0, yellow_s=0.5),
        )
        unresolved = [movement.id for movement in intersection.movements if not movement.resolved]
        self.assertTrue(unresolved)
        for _ in range(40):
            for movement_id in unresolved:
                self.assertEqual(controller.state_for_movement(movement_id), SignalState.RED)
                self.assertFalse(controller.movement_permitted(movement_id))
            controller.tick(0.25)

    def test_large_tick_matches_equivalent_small_ticks(self) -> None:
        intersection = four_way()
        timing = TimingPolicy(clearance_s=0.75, red_yellow_s=1.0, green_s=2.5, yellow_s=1.25)
        large = IntersectionSignalController(intersection, timing)
        small = IntersectionSignalController(intersection, timing)

        large.tick(19.75)
        for _ in range(79):
            small.tick(0.25)

        self.assertEqual(large.phase_index, small.phase_index)
        self.assertEqual(large.stage, small.stage)
        self.assertAlmostEqual(large.elapsed_s, small.elapsed_s, places=9)
        for movement in intersection.movements:
            self.assertEqual(large.state_for_movement(movement.id), small.state_for_movement(movement.id))

    def test_reset_and_restore_are_safe_and_deterministic(self) -> None:
        controller = IntersectionSignalController(four_way(), TimingPolicy())
        controller.tick(6.25)
        saved = controller.snapshot()
        restored = IntersectionSignalController(four_way(), TimingPolicy())
        restored.restore(saved)
        self.assertEqual(restored.snapshot(), saved)

        controller.reset()
        self.assertEqual(controller.snapshot(), ControllerSnapshot(0, ControllerStage.ALL_RED, 0.0))
        self.assertTrue(all(controller.state_for_movement(m.id) == SignalState.RED for m in controller.intersection.movements))

    def test_invalid_timing_dt_and_snapshot_fail_closed(self) -> None:
        with self.assertRaises(ValueError):
            TimingPolicy(green_s=0.0)
        controller = IntersectionSignalController(four_way())
        with self.assertRaises(ValueError):
            controller.tick(-0.01)
        with self.assertRaises(ValueError):
            controller.restore(ControllerSnapshot(999, ControllerStage.GREEN, 0.0))
        with self.assertRaises(ValueError):
            controller.restore(ControllerSnapshot(0, ControllerStage.GREEN, controller.timing.green_s))
        with self.assertRaises(KeyError):
            controller.state_for_movement("missing")


if __name__ == "__main__":
    unittest.main()
