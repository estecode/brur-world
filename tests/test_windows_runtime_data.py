"""Tests the production-only runtime-data subset used by Windows exports."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "windows_build" / "prepare_runtime_data.py"
spec = importlib.util.spec_from_file_location("windows_runtime_data", MODULE_PATH)
assert spec and spec.loader
windows_runtime_data = importlib.util.module_from_spec(spec)
spec.loader.exec_module(windows_runtime_data)


class WindowsRuntimeDataTests(unittest.TestCase):
    def _source_fixture(self, root: Path) -> Path:
        source = root / "world_data"
        source.mkdir()
        for name in windows_runtime_data.REQUIRED_FILES:
            (source / name).write_bytes((name + "\n").encode("utf-8"))
        (source / "routing_stats.json").write_text("{}\n", encoding="utf-8")
        for name in windows_runtime_data.REQUIRED_DIRS:
            directory = source / name
            directory.mkdir()
            (directory / "0_0.bin").write_bytes(b"runtime")
        (source / "buildings.jsonl").write_bytes(b"rebuild-only")
        (source / "pois.jsonl").write_bytes(b"rebuild-only")
        (source / "search_index.jsonl").write_bytes(b"rebuild-only")
        cache = source / "osm_source_cache"
        cache.mkdir()
        (cache / "areas.osm").write_bytes(b"source-cache")
        return source

    def test_prepare_copies_runtime_and_excludes_rebuild_sources(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self._source_fixture(root)
            output = root / "runtime"
            copied = windows_runtime_data.prepare_runtime_data(source, output)
            for name in windows_runtime_data.REQUIRED_FILES:
                self.assertTrue((output / name).is_file(), name)
            for name in windows_runtime_data.REQUIRED_DIRS:
                self.assertTrue((output / name / "0_0.bin").is_file(), name)
            self.assertTrue((output / "routing_stats.json").is_file())
            self.assertFalse((output / "buildings.jsonl").exists())
            self.assertFalse((output / "pois.jsonl").exists())
            self.assertFalse((output / "search_index.jsonl").exists())
            self.assertFalse((output / "osm_source_cache").exists())
            self.assertIn("manifest.json", copied)
            self.assertIn("building_tiles/0_0.bin", copied)

    def test_missing_required_file_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self._source_fixture(root)
            (source / "background.brmap").unlink()
            with self.assertRaises(SystemExit):
                windows_runtime_data.prepare_runtime_data(source, root / "runtime")

    def test_empty_required_directory_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = self._source_fixture(root)
            for path in (source / "lod0").iterdir():
                path.unlink()
            with self.assertRaises(SystemExit):
                windows_runtime_data.prepare_runtime_data(source, root / "runtime")


if __name__ == "__main__":
    unittest.main()
