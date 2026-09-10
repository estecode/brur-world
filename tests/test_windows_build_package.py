"""Validates the reusable Windows client packaging contract with synthetic files.

Dependencies:
- Imports tools/windows_build/package.py directly.
- Checks the selected-revision target invokes the existing showcase preparation CLI correctly.
- Uses temporary synthetic binaries/runtime data; it does not require Godot or real world data.
"""

from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "windows_build" / "package.py"
TARGET_PATH = ROOT / "tools" / "windows_build" / "target.sh"
spec = importlib.util.spec_from_file_location("windows_package", MODULE_PATH)
assert spec and spec.loader
windows_package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(windows_package)


class WindowsPackageTests(unittest.TestCase):
    def _fixture(self, root: Path) -> tuple[Path, Path, Path, Path]:
        binary = root / "binary"
        runtime = root / "runtime"
        binary.mkdir()
        runtime.mkdir()
        (binary / "brur-deadbeef0000-win64.exe").write_bytes(b"exe")
        (binary / "brur-deadbeef0000-win64.pck").write_bytes(b"pck")
        (runtime / "manifest.json").write_text('{"runtime": true}', encoding="utf-8")
        nested = runtime / "tiles"
        nested.mkdir()
        (nested / "city.bin").write_bytes(b"world")
        source_manifest = root / "source_manifest.json"
        source_manifest.write_text('{"generation": "same"}', encoding="utf-8")
        build_info = root / "build_info.json"
        build_info.write_text(
            json.dumps(
                {
                    "repository": "estecode/brur-world",
                    "selector": {"kind": "pr", "value": "321"},
                    "pr": 321,
                    "issue": 320,
                    "ref": "issue/320-example",
                    "commit": "d" * 40,
                    "short_commit": "d" * 12,
                    "godot_version": "4.7.2.stable",
                    "export_target": "Windows Desktop",
                    "client_ready": False,
                }
            ),
            encoding="utf-8",
        )
        return binary, runtime, build_info, source_manifest

    def test_package_contains_identity_runtime_and_logs_directory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary, runtime, build_info, source_manifest = self._fixture(root)
            output = root / "out" / "client.zip"
            report = windows_package.package_client(binary, runtime, build_info, source_manifest, output)

            self.assertEqual(report["pr"], 321)
            self.assertEqual(report["commit"], "d" * 40)
            with zipfile.ZipFile(output) as archive:
                names = set(archive.namelist())
                self.assertIn("BRUR/logs/", names)
                self.assertIn("BRUR/runtime_data/manifest.json", names)
                self.assertIn("BRUR/runtime_data/tiles/city.bin", names)
                packaged_build = json.loads(archive.read("BRUR/build_info.json"))
                packaged_bundle = json.loads(archive.read("BRUR/client_bundle_info.json"))

            self.assertTrue(packaged_build["client_ready"])
            self.assertEqual(
                packaged_build["runtime_files"]["tiles/city.bin"],
                windows_package.sha256(runtime / "tiles" / "city.bin"),
            )
            self.assertEqual(
                packaged_bundle["world_data_source_manifest_sha256"],
                windows_package.sha256(source_manifest),
            )

    def test_missing_matching_pck_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary, runtime, build_info, source_manifest = self._fixture(root)
            (binary / "brur-deadbeef0000-win64.pck").unlink()
            with self.assertRaises(SystemExit):
                windows_package.package_client(binary, runtime, build_info, source_manifest, root / "client.zip")

    def test_empty_runtime_data_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary, runtime, build_info, source_manifest = self._fixture(root)
            for path in sorted(runtime.rglob("*"), reverse=True):
                if path.is_file():
                    path.unlink()
                elif path.is_dir():
                    path.rmdir()
            with self.assertRaises(SystemExit):
                windows_package.package_client(binary, runtime, build_info, source_manifest, root / "client.zip")

    def test_target_passes_required_output_flag_to_showcase_preparer(self) -> None:
        target = TARGET_PATH.read_text(encoding="utf-8")
        self.assertIn(
            '"$BRUR_WINDOWS_WORLD_DATA" --output "$BRUR_WINDOWS_RUNTIME_DATA_OUT"',
            target,
        )


if __name__ == "__main__":
    unittest.main()
