"""Guards the production Godot startup scene from harness/POC overrides."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ProjectEntrypointTests(unittest.TestCase):
    def test_main_project_starts_production_scene(self) -> None:
        project = (ROOT / "project.godot").read_text(encoding="utf-8")
        self.assertIn('run/main_scene="res://scenes/main.tscn"', project)
        self.assertNotIn(".poc_runtime", project)
        self.assertNotIn("res://harness/", project)


if __name__ == "__main__":
    unittest.main()
