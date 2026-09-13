"""Validates the reusable Windows client packaging contract with synthetic files.

Dependencies:
- Imports tools/windows_build/package.py directly.
- Checks the selected-revision target keeps stable world data out of the game PCK.
- Uses temporary synthetic binaries/runtime packs; it does not require Godot or real world data.
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
PROJECT_PATH = ROOT / "project.godot"
LOADER_PATH = ROOT / "scripts" / "windows_runtime_pack_loader.gd"
spec = importlib.util.spec_from_file_location("windows_package", MODULE_PATH)
assert spec and spec.loader
windows_package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(windows_package)


class WindowsPackageTests(unittest.TestCase):
    def _fixture(self, root: Path) -> tuple[Path, Path, Path, Path, Path]:
        binary = root / "binary"
        binary.mkdir()
        (binary / "brur-deadbeef0000-win64.exe").write_bytes(b"exe")
        (binary / "brur-deadbeef0000-win64.pck").write_bytes(b"pck")

        runtime_pack = root / "brur-world-data.zip"
        with zipfile.ZipFile(runtime_pack, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("world_data/manifest.json", '{"runtime": true}')
            archive.writestr("world_data/tiles/city.bin", b"world")
            archive.writestr(
                "world_data/windows_runtime_manifest.json",
                json.dumps({"schema_version": 3, "files": ["manifest.json", "tiles/city.bin"]}),
            )

        runtime_info = root / "runtime_pack_info.json"
        runtime_info.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "pack_format_version": 1,
                    "pack_path": str(runtime_pack),
                    "pack_filename": "brur-world-data.zip",
                    "fingerprint": "f" * 64,
                    "runtime_files": {
                        "manifest.json": "a" * 64,
                        "tiles/city.bin": "b" * 64,
                    },
                    "cache_hit": True,
                }
            ),
            encoding="utf-8",
        )

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
        return binary, runtime_info, build_info, source_manifest, runtime_pack

    def test_package_records_external_runtime_identity_without_duplicate_data(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary, runtime_info, build_info, source_manifest, runtime_pack = self._fixture(root)
            output = root / "out" / "client.zip"
            report = windows_package.package_client(binary, runtime_info, build_info, source_manifest, output)

            self.assertEqual(report["pr"], 321)
            self.assertEqual(report["commit"], "d" * 40)
            self.assertEqual(
                report["runtime_delivery"],
                "resource_pack:brur-world-data.zip=>res://world_data",
            )
            with zipfile.ZipFile(output) as archive:
                names = set(archive.namelist())
                self.assertIn("BRUR/logs/", names)
                self.assertIn("BRUR/brur-world-data.zip", names)
                self.assertFalse(any(name.startswith("BRUR/runtime_data/") for name in names))
                self.assertEqual(archive.read("BRUR/brur-deadbeef0000-win64.exe"), b"exe")
                self.assertEqual(archive.read("BRUR/brur-deadbeef0000-win64.pck"), b"pck")
                self.assertEqual(archive.read("BRUR/brur-world-data.zip"), runtime_pack.read_bytes())
                self.assertEqual(
                    archive.getinfo("BRUR/brur-world-data.zip").compress_type,
                    zipfile.ZIP_STORED,
                )
                packaged_build = json.loads(archive.read("BRUR/build_info.json"))
                packaged_bundle = json.loads(archive.read("BRUR/client_bundle_info.json"))

            self.assertTrue(packaged_build["client_ready"])
            self.assertEqual(packaged_build["packaging_format_version"], 3)
            self.assertTrue(packaged_build["runtime_pack_cache_hit"])
            self.assertEqual(packaged_build["runtime_pack_fingerprint"], "f" * 64)
            self.assertEqual(packaged_build["runtime_files"]["tiles/city.bin"], "b" * 64)
            self.assertEqual(
                packaged_bundle["world_data_source_manifest_sha256"],
                windows_package.sha256(source_manifest),
            )

    def test_package_streams_cached_runtime_pack_without_recompression(self) -> None:
        source = MODULE_PATH.read_text(encoding="utf-8")
        self.assertNotIn("runtime_hashes", source)
        self.assertIn("compress_type=zipfile.ZIP_STORED", source)
        self.assertIn('archive.write(runtime_pack, f"BRUR/{pack_filename}"', source)

    def test_missing_matching_pck_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary, runtime_info, build_info, source_manifest, _runtime_pack = self._fixture(root)
            (binary / "brur-deadbeef0000-win64.pck").unlink()
            with self.assertRaises(SystemExit):
                windows_package.package_client(binary, runtime_info, build_info, source_manifest, root / "client.zip")

    def test_missing_runtime_pack_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary, runtime_info, build_info, source_manifest, runtime_pack = self._fixture(root)
            runtime_pack.unlink()
            with self.assertRaises(SystemExit):
                windows_package.package_client(binary, runtime_info, build_info, source_manifest, root / "client.zip")

    def test_target_keeps_world_data_out_of_game_pck(self) -> None:
        target = TARGET_PATH.read_text(encoding="utf-8")
        self.assertIn("runtime_pack.py", target)
        self.assertIn("BRUR_WINDOWS_RUNTIME_PACK_INFO", target)
        self.assertNotIn('STAGED_WORLD_DATA="$BRUR_WINDOWS_SOURCE_ROOT/world_data"', target)
        self.assertNotIn('include_filter="world_data/*,world_data/**/*"', target)
        self.assertNotIn('cp -R "$BRUR_WINDOWS_RUNTIME_DATA_OUT"', target)
        self.assertIn('--main-pack "$PCK_PATH"', target)
        self.assertIn("test_windows_packaged_world_data.gd", target)
        self.assertIn('"$RUNTIME_PACK_PATH"', target)

    def test_target_preserves_selected_revision_production_entrypoint(self) -> None:
        target = TARGET_PATH.read_text(encoding="utf-8")
        self.assertNotIn("project.godot", "\n".join(
            line for line in target.splitlines() if not line.startswith("#")
        ))
        self.assertNotIn("world_showcase.tscn", target)
        self.assertNotIn("world_showcase_windows.tscn", target)
        self.assertIn('--export-release "Windows Desktop"', target)

    def test_windows_autoload_mounts_pack_before_main_scene(self) -> None:
        project = PROJECT_PATH.read_text(encoding="utf-8")
        loader = LOADER_PATH.read_text(encoding="utf-8")
        self.assertIn('[autoload]', project)
        self.assertIn('WindowsRuntimePack="*res://scripts/windows_runtime_pack_loader.gd"', project)
        self.assertIn('OS.has_feature("windows")', loader)
        self.assertIn('ProjectSettings.load_resource_pack(pack_path, true)', loader)
        self.assertIn('FileAccess.file_exists(REQUIRED_MANIFEST)', loader)
        self.assertIn('get_tree().quit(78)', loader)


if __name__ == "__main__":
    unittest.main()
