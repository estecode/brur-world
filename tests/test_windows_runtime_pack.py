"""Tests the content-addressed Windows runtime resource-pack cache."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "windows_build" / "runtime_pack.py"
spec = importlib.util.spec_from_file_location("windows_runtime_pack", MODULE_PATH)
assert spec and spec.loader
runtime_pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime_pack)

prepare_module = runtime_pack.sys.modules.get("prepare_runtime_data")
if prepare_module is None:
    import prepare_runtime_data as prepare_module  # type: ignore[no-redef]


class WindowsRuntimePackTests(unittest.TestCase):
    def _source_fixture(self, root: Path) -> Path:
        source = root / "world_data"
        source.mkdir()
        for name in prepare_module.REQUIRED_FILES:
            (source / name).write_bytes((name + "\n").encode("utf-8"))
        (source / "routing_stats.json").write_text("{}\n", encoding="utf-8")
        for name in prepare_module.REQUIRED_DIRS:
            directory = source / name
            directory.mkdir()
            (directory / "0_0.bin").write_bytes((name + " runtime").encode("utf-8"))
        obsolete = source / "building_tiles"
        obsolete.mkdir()
        (obsolete / "0_0.jsonl").write_text("obsolete\n", encoding="utf-8")
        return source

    def test_second_unchanged_build_reuses_hashes_and_pack(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self._source_fixture(root)
            cache = root / "cache"

            first = runtime_pack.prepare_cached_runtime_pack(source, cache)
            second = runtime_pack.prepare_cached_runtime_pack(source, cache)

            self.assertFalse(first["cache_hit"])
            self.assertGreater(first["files_rehashed"], 0)
            self.assertTrue(second["cache_hit"])
            self.assertEqual(second["files_rehashed"], 0)
            self.assertEqual(second["hashes_reused"], len(second["runtime_files"]))
            self.assertEqual(first["fingerprint"], second["fingerprint"])
            self.assertEqual(first["pack_path"], second["pack_path"])

    def test_cold_and_warm_runs_explain_progress_and_shipping_mode(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self._source_fixture(root)
            cache = root / "cache"

            cold_output = io.StringIO()
            with contextlib.redirect_stdout(cold_output):
                runtime_pack.prepare_cached_runtime_pack(source, cache)
            cold = cold_output.getvalue()
            self.assertIn("WINDOWS BUILD — PACKING + SHIPPING", cold)
            self.assertIn("[runtime-pack] checking", cold)
            self.assertIn("WINDOWS_RUNTIME_RAW_TOTAL=", cold)
            self.assertIn("WINDOWS_RUNTIME_RAW category=building_mesh_lod", cold)
            self.assertIn("[runtime-pack] hashing", cold)
            self.assertIn("[runtime-pack] packing", cold)
            self.assertIn("[runtime-pack] verifying", cold)
            self.assertIn("WINDOWS_RUNTIME_PACK=MISS", cold)

            warm_output = io.StringIO()
            with contextlib.redirect_stdout(warm_output):
                runtime_pack.prepare_cached_runtime_pack(source, cache)
            warm = warm_output.getvalue()
            self.assertIn("WINDOWS BUILD — SHIPPING", warm)
            self.assertIn("0 files changed — no content reread", warm)
            self.assertIn("WINDOWS_RUNTIME_PACK=HIT", warm)
            self.assertIn("rehashed=0", warm)

    def test_metadata_change_rehashes_only_changed_file_and_changes_fingerprint(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self._source_fixture(root)
            cache = root / "cache"
            first = runtime_pack.prepare_cached_runtime_pack(source, cache)

            changed = source / "routing_stats.json"
            old_stat = changed.stat()
            changed.write_text('{"changed":1}\n', encoding="utf-8")
            os.utime(changed, ns=(old_stat.st_atime_ns, old_stat.st_mtime_ns))

            second = runtime_pack.prepare_cached_runtime_pack(source, cache)
            self.assertFalse(second["cache_hit"])
            self.assertEqual(second["files_rehashed"], 1)
            self.assertNotEqual(first["fingerprint"], second["fingerprint"])

    def test_corrupt_cached_pack_is_rebuilt(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self._source_fixture(root)
            cache = root / "cache"
            first = runtime_pack.prepare_cached_runtime_pack(source, cache)
            pack = Path(first["pack_path"])
            pack.write_bytes(b"not a zip")

            second = runtime_pack.prepare_cached_runtime_pack(source, cache)
            self.assertFalse(second["cache_hit"])
            self.assertTrue(zipfile.is_zipfile(pack))
            with zipfile.ZipFile(pack) as archive:
                self.assertIn("world_data/windows_runtime_manifest.json", archive.namelist())

    def test_pack_contains_current_runtime_selection_only(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self._source_fixture(root)
            report = runtime_pack.prepare_cached_runtime_pack(source, root / "cache")
            with zipfile.ZipFile(report["pack_path"]) as archive:
                names = set(archive.namelist())
                self.assertIn("world_data/building_mesh_lod/0_0.bin", names)
                self.assertNotIn("world_data/building_tiles/0_0.jsonl", names)
                manifest = json.loads(archive.read("world_data/windows_runtime_manifest.json"))
            self.assertEqual(report["pack_format_version"], 1)
            self.assertEqual(manifest["fingerprint"], report["fingerprint"])
            self.assertEqual(manifest["sha256"], report["runtime_files"])

    def test_obsolete_stored_pack_cache_is_removed_before_build(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self._source_fixture(root)
            cache = root / "cache"
            pack_dir = cache / "runtime-packs"
            pack_dir.mkdir(parents=True)
            fingerprint = "a" * 64
            obsolete_pack = pack_dir / f"{fingerprint}.zip"
            obsolete_pack.write_bytes(b"obsolete raw pack")
            (pack_dir / f"{fingerprint}.zip.json").write_text(
                json.dumps({"pack_format_version": 2, "fingerprint": fingerprint}),
                encoding="utf-8",
            )
            shipping = pack_dir / f"{fingerprint}.shipping-base-v1.zip"
            shipping.write_bytes(b"obsolete shipping base")
            (pack_dir / f"{fingerprint}.shipping-base-v1.zip.json").write_text("{}", encoding="utf-8")

            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                runtime_pack.prepare_cached_runtime_pack(source, cache)

            self.assertFalse(obsolete_pack.exists())
            self.assertFalse(shipping.exists())
            self.assertIn("WINDOWS_RUNTIME_CACHE_CLEANUP", output.getvalue())


if __name__ == "__main__":
    unittest.main()
