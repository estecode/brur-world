"""Compile and run the portable C++ waypoint route-plan contract tests.

Dependencies:
- Requires a local C++20 compiler (CXX, clang++, or g++).
- Does not require Sweden world data, Godot, sockets, or network access.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tests" / "native" / "test_gps_route_plan.cpp"


class NativeRoutePlanTests(unittest.TestCase):
    def test_portable_cpp_contract(self) -> None:
        compiler = os.environ.get("CXX") or shutil.which("clang++") or shutil.which("g++")
        if not compiler:
            self.skipTest("no C++20 compiler available")

        with tempfile.TemporaryDirectory(prefix="brur-native-route-plan-") as temp_dir:
            binary = Path(temp_dir) / "test_gps_route_plan"
            subprocess.run(
                [
                    compiler,
                    "-std=c++20",
                    "-O2",
                    "-Wall",
                    "-Wextra",
                    "-pedantic",
                    str(SOURCE),
                    "-o",
                    str(binary),
                ],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            completed = subprocess.run(
                [str(binary)],
                cwd=ROOT,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertEqual(completed.stdout.strip(), "native gps route-plan tests: OK")


if __name__ == "__main__":
    unittest.main()
