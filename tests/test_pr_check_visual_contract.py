import os
import pathlib
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class PrCheckVisualContractTests(unittest.TestCase):
    def _run_local_check(self, manual_check: str, changed_files: str = "scripts/gps_route_layer.gd"):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = pathlib.Path(temp_dir)
            world_data = temp / "world_data"
            world_data.mkdir()
            godot_log = temp / "godot.log"
            fake_godot = temp / "godot"
            fake_godot.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                f"printf '%s\\n' \"$*\" >> {godot_log!s}\n",
                encoding="utf-8",
            )
            fake_godot.chmod(0o755)

            env = os.environ.copy()
            env.update(
                {
                    "BRUR_PR_CHECK_PR": "255",
                    "BRUR_PR_CHECK_WORKTREE": str(ROOT),
                    "BRUR_PR_CHECK_WORLD_DATA": str(world_data),
                    "BRUR_PR_CHECK_CHANGED_FILES": changed_files,
                    "BRUR_PR_CHECK_MANUAL_REVIEW": manual_check,
                    "PYTHON_BIN": sys.executable,
                    "GODOT_BIN": str(fake_godot),
                }
            )
            result = subprocess.run(
                ["bash", str(ROOT / "tools/pr_check_local.sh")],
                cwd=ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            launched = godot_log.read_text(encoding="utf-8") if godot_log.exists() else ""
            return result, launched

    def test_explicit_manual_review_launches_production_game_even_when_file_scope_would_skip(self) -> None:
        result, launched = self._run_local_check("required")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PR_CHECK=VISUAL_REVIEW pr=255", result.stdout)
        self.assertIn("reason=pr-merge-decision", result.stdout)
        self.assertNotIn("PR_CHECK=SKIP_VISUAL_REVIEW", result.stdout)
        self.assertIn("scenes/main.tscn", launched)
        self.assertNotIn("--editor", launched)

    def test_no_manual_review_keeps_scope_based_skip(self) -> None:
        result, launched = self._run_local_check("none")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PR_CHECK=SKIP_VISUAL_REVIEW", result.stdout)
        self.assertEqual(launched, "")


if __name__ == "__main__":
    unittest.main()
