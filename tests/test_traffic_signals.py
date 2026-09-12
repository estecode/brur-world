"""Tests normalized traffic-signal import and portable runtime data.

Dependencies:
- Uses the production offline traffic-signal builder and normalizer.
- Uses only tiny temporary OSM fixtures; no Godot or rendered world state.
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

import build_traffic_signals as traffic_signal_builder
from build_traffic_signals import build_traffic_signals
from traffic_signals import FORMAT, SignalDraft, build_runtime_dataset, load_runtime_dataset
from world_common import project


FIXTURE = """<?xml version="1.0" encoding="UTF-8"?>
<osm version="0.6">
  <node id="1" lat="59.0" lon="18.0">
    <tag k="highway" v="traffic_signals"/>
    <tag k="traffic_signals:direction" v="forward"/>
    <tag k="road_marking" v="stop_line"/>
    <tag k="traffic_signals" v="signal"/>
  </node>
  <node id="2" lat="59.0001" lon="18.0001">
    <tag k="highway" v="traffic_signals"/>
    <tag k="direction" v="backward"/>
  </node>
  <node id="3" lat="59.0002" lon="18.0002">
    <tag k="highway" v="traffic_signals"/>
  </node>
  <node id="4" lat="59.0003" lon="18.0003"/>
  <way id="101">
    <nd ref="4"/><nd ref="1"/><nd ref="2"/>
    <tag k="highway" v="primary"/>
  </way>
  <way id="102">
    <nd ref="4"/><nd ref="1"/><nd ref="3"/>
    <tag k="highway" v="secondary"/>
  </way>
</osm>
"""


class TrafficSignalTests(unittest.TestCase):
    def test_normalization_is_stable_and_preserves_unknowns(self) -> None:
        x, y = project(18.0, 59.0)
        drafts = [
            SignalDraft(3, x + 2, y + 2, {"highway": "traffic_signals"}, (102,)),
            SignalDraft(
                1,
                x,
                y,
                {
                    "highway": "traffic_signals",
                    "traffic_signals:direction": "forward",
                    "road_marking": "stop_line",
                },
                (101, 102),
            ),
        ]
        dataset = build_runtime_dataset(reversed(drafts))
        self.assertEqual([signal["osm_node_id"] for signal in dataset["signals"]], [1, 3])
        self.assertEqual(dataset["signals"][0]["direction"], "forward")
        self.assertEqual(dataset["signals"][0]["direction_source"], "explicit")
        self.assertTrue(dataset["signals"][0]["explicit_stop_line"])
        self.assertEqual(dataset["signals"][0]["group_candidate_id"], "junction-node:1")
        self.assertIsNone(dataset["signals"][1]["direction"])
        self.assertEqual(dataset["signals"][1]["direction_source"], "unknown")
        self.assertIsNone(dataset["signals"][1]["group_candidate_id"])

    def test_fixture_build_round_trips_and_uses_shared_projection(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            fixture = root / "signals.osm"
            output = root / "world_data"
            fixture.write_text(FIXTURE, encoding="utf-8")

            stats = build_traffic_signals(fixture, output)
            dataset = load_runtime_dataset(output / "traffic_signals.json")

            self.assertEqual(dataset["format"], FORMAT)
            self.assertEqual(stats["source_signal_count"], 3)
            self.assertEqual(stats["exported_signal_count"], 3)
            self.assertEqual(stats["explicit_direction_count"], 1)
            self.assertEqual(stats["legacy_direction_count"], 1)
            self.assertEqual(stats["unknown_direction_count"], 1)
            self.assertEqual(stats["explicit_stop_line_count"], 1)
            self.assertEqual(stats["grouped_candidate_count"], 1)
            self.assertFalse(stats["reused"])

            first = dataset["signals"][0]
            expected_x, expected_y = project(18.0, 59.0)
            self.assertAlmostEqual(first["x"], expected_x)
            self.assertAlmostEqual(first["y"], expected_y)
            self.assertEqual(first["highway_way_ids"], [101, 102])

            manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
            entry = manifest["traffic_signals"]
            self.assertEqual(entry["format"], "BTS1")
            self.assertEqual(entry["file"], "traffic_signals.json")
            self.assertEqual(entry["source"]["algorithm"], "sha256")
            self.assertEqual(len(entry["source"]["digest"]), 64)
            self.assertEqual(entry["source"]["size_bytes"], fixture.stat().st_size)

    def test_unchanged_source_reuses_valid_output_without_source_scan(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            fixture = root / "signals.osm"
            output = root / "world_data"
            fixture.write_text(FIXTURE, encoding="utf-8")
            build_traffic_signals(fixture, output)

            with patch.object(traffic_signal_builder, "_source", side_effect=AssertionError("source scan must not run")):
                stats = build_traffic_signals(fixture, output)

            self.assertTrue(stats["reused"])
            self.assertEqual(stats["source_signal_count"], 3)

    def test_changed_source_hash_forces_rebuild(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            fixture = root / "signals.osm"
            output = root / "world_data"
            fixture.write_text(FIXTURE, encoding="utf-8")
            build_traffic_signals(fixture, output)
            fixture.write_text(FIXTURE + "\n", encoding="utf-8")

            original_source = traffic_signal_builder._source
            with patch.object(traffic_signal_builder, "_source", wraps=original_source) as source_scan:
                stats = build_traffic_signals(fixture, output)

            self.assertEqual(source_scan.call_count, 1)
            self.assertFalse(stats["reused"])

    def test_missing_or_invalid_output_forces_rebuild(self) -> None:
        for invalid_contents in (None, "not-json"):
            with self.subTest(invalid_contents=invalid_contents):
                with tempfile.TemporaryDirectory() as temp_dir:
                    root = Path(temp_dir)
                    fixture = root / "signals.osm"
                    output = root / "world_data"
                    fixture.write_text(FIXTURE, encoding="utf-8")
                    build_traffic_signals(fixture, output)
                    destination = output / "traffic_signals.json"
                    if invalid_contents is None:
                        destination.unlink()
                    else:
                        destination.write_text(invalid_contents, encoding="utf-8")

                    original_source = traffic_signal_builder._source
                    with patch.object(traffic_signal_builder, "_source", wraps=original_source) as source_scan:
                        stats = build_traffic_signals(fixture, output)

                    self.assertEqual(source_scan.call_count, 1)
                    self.assertFalse(stats["reused"])
                    self.assertEqual(load_runtime_dataset(destination)["format"], FORMAT)

    def test_unsupported_direction_degrades_to_unknown(self) -> None:
        dataset = build_runtime_dataset(
            [SignalDraft(7, 0.0, 0.0, {"traffic_signals:direction": "sideways"}, (1,))]
        )
        signal = dataset["signals"][0]
        self.assertIsNone(signal["direction"])
        self.assertEqual(signal["direction_source"], "unknown")


if __name__ == "__main__":
    unittest.main()
