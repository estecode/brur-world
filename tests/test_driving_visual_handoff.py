import os
import pathlib
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class DrivingVisualHandoffTests(unittest.TestCase):
    def test_driving_harness_change_launches_driving_visual_review(self) -> None:
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
                    "BRUR_PR_CHECK_PR": "246",
                    "BRUR_PR_CHECK_WORKTREE": str(ROOT),
                    "BRUR_PR_CHECK_WORLD_DATA": str(world_data),
                    "BRUR_PR_CHECK_CHANGED_FILES": "harness/driving/test_vehicle_route_recovery.gd",
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
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("PR_CHECK=VISUAL_REVIEW pr=246", result.stdout)
            self.assertNotIn("PR_CHECK=SKIP_VISUAL_REVIEW", result.stdout)
            self.assertIn("Driving policy Normal, Aggressive and Maniac", result.stdout)
            launched = godot_log.read_text(encoding="utf-8")
            self.assertIn("harness/driving/driving_harness.tscn", launched)


if __name__ == "__main__":
    unittest.main()
