"""Verify #220's pyrosm stage writes one opaque domain result at a time."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from pyrosm_source_stage import DOMAINS, extract_source_stage


class OpaqueFrame:
    def __len__(self):
        raise AssertionError("orchestrator must not inspect pyrosm result length")

    def __iter__(self):
        raise AssertionError("orchestrator must not iterate pyrosm result")

    def __getattr__(self, name):
        raise AssertionError(f"orchestrator must not inspect pyrosm result attribute: {name}")


class FakeOSM:
    def __init__(self):
        self.calls: list[str] = []
        self.current_domain = ""

    def get_network(self, **kwargs):
        self.current_domain = "highways"
        self.calls.append("highways")
        return OpaqueFrame()

    def get_data_by_custom_criteria(self, *, custom_filter, filter_type):
        text = str(custom_filter)
        if "building" in text:
            domain = "buildings"
        elif "addr:housenumber" in text:
            domain = "addresses"
        elif "traffic_signals" in text:
            domain = "traffic_signals"
        elif "boundary" in text and "coastline" in text:
            domain = "background"
        else:
            domain = "pois"
        self.current_domain = domain
        self.calls.append(domain)
        return OpaqueFrame()

    def write_pbf(self, frame, path, subset_only=True):
        self.calls.append(f"write:{self.current_domain}")
        Path(path).write_bytes((self.current_domain + "\n").encode("utf-8"))


class Tests(unittest.TestCase):
    def test_all_domains_are_written_sequentially_without_result_inspection(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "fixture.osm.pbf"
            source.write_bytes(b"source")
            output = root / "stage"
            fake = FakeOSM()

            report = extract_source_stage(source, output, DOMAINS, osm_and_version=(fake, "0.13.1"))

            self.assertEqual(report["status"], "DONE")
            self.assertEqual(report["domains"], list(DOMAINS))
            self.assertEqual(
                fake.calls,
                [item for domain in DOMAINS for item in (domain, f"write:{domain}")],
            )
            for domain in DOMAINS:
                self.assertEqual((output / f"{domain}.osm.pbf").read_text(encoding="utf-8"), f"{domain}\n")
            manifest = json.loads((output / "extract_manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(set(manifest["results"]), set(DOMAINS))

    def test_unknown_domain_fails_before_extraction(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "fixture.osm.pbf"
            source.write_bytes(b"source")
            with self.assertRaises(ValueError):
                extract_source_stage(source, root / "stage", ("buildings", "nope"), osm_and_version=(FakeOSM(), "0.13.1"))


if __name__ == "__main__":
    unittest.main()
