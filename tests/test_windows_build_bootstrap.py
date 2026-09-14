"""Regression coverage for the stable Windows Safe Command bootstrap contract."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP_PATH = ROOT / "tools" / "windows_build.sh"
BUILDER_PATH = ROOT / "tools" / "windows_build" / "build.sh"


class WindowsBuildBootstrapTests(unittest.TestCase):
    def test_normal_bootstrap_pins_mapped_checkout_world_data(self) -> None:
        source = BOOTSTRAP_PATH.read_text(encoding="utf-8")
        symlink = 'ln -s "$ROOT/world_data" "$LAUNCHER_TMP/world_data"'
        pin = 'export BRUR_WINDOWS_WORLD_DATA="$ROOT/world_data"'
        launch = 'bash tools/windows_build/build.sh "$@"'

        self.assertIn(symlink, source)
        self.assertIn(pin, source)
        self.assertIn(launch, source)
        self.assertLess(source.index(symlink), source.index(pin))
        self.assertLess(source.index(pin), source.index(launch))

    def test_lower_level_builder_keeps_explicit_world_data_override(self) -> None:
        source = BUILDER_PATH.read_text(encoding="utf-8")
        self.assertIn('WORLD_DATA="${BRUR_WINDOWS_WORLD_DATA:-$ROOT/world_data}"', source)


if __name__ == "__main__":
    unittest.main()
