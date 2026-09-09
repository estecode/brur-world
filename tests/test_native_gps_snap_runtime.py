"""Compile and execute the portable zero-allocation BRS3 snap runtime contract.

Dependencies:
- Requires a local C++20 compiler (CXX, clang++, or g++).
- Uses only native/gps_snap_runtime and its in-memory fixture test.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "native" / "gps_snap_runtime.cpp"
TEST = ROOT / "tests" / "native" / "test_gps_snap_runtime.cpp"


class NativeGpsSnapRuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.compiler = os.environ.get("CXX") or shutil.which("clang++") or shutil.which("g++")

    def test_zero_allocation_fixed_point_snap_contract(self) -> None:
        if not self.compiler:
            self.skipTest("no C++20 compiler available")
        with tempfile.TemporaryDirectory(prefix="brur-native-gps-snap-") as temp_dir:
            binary = Path(temp_dir) / "test_gps_snap_runtime"
            subprocess.run(
                [
                    self.compiler,
                    "-std=c++20",
                    "-O2",
                    "-Wall",
                    "-Wextra",
                    "-pedantic",
                    str(SOURCE),
                    str(TEST),
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
            self.assertEqual(completed.stdout.strip(), "native gps snap runtime tests: OK")


if __name__ == "__main__":
    unittest.main()
