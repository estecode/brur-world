from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "pr_check_local.sh"


class SafeCheckHandoffContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = SCRIPT.read_text(encoding="utf-8")

    def test_geodot_handoff_requires_objective_completion_marker(self):
        objective = self.text.index("PR_CHECK=GEODOT_OBJECTIVE_OK")
        ready = self.text.index("PR_CHECK=HANDOFF_READY objective=geodot")
        visual = self.text.index("PR_CHECK=VISUAL_REVIEW pr=")
        self.assertLess(objective, ready)
        self.assertLess(ready, visual)

    def test_objective_stages_emit_begin_ok_and_fail_diagnostics(self):
        self.assertIn("PR_CHECK=STAGE_BEGIN", self.text)
        self.assertIn("PR_CHECK=STAGE_OK", self.text)
        self.assertIn("PR_CHECK=STAGE_FAIL", self.text)
        self.assertIn("else status=$?", self.text)

    def test_sweden_pbf_discovery_skips_missing_search_directories(self):
        self.assertIn('for dir in "$root/syndicate/data" "$root/data"', self.text)
        self.assertIn('[[ -d "$dir" ]] || continue', self.text)
        self.assertIn("tail -n1 || true", self.text)

    def test_geodot_visual_handoff_fails_closed_without_resolved_gpkg(self):
        self.assertIn("refusing GeoDot visual handoff without completed GeoDot objective state", self.text)


if __name__ == "__main__":
    unittest.main()
