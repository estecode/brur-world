"""Tests the persistent local PR-check GitHub status adapter.

Dependencies:
- Standard library unittest/mock only.
- Imports tools/pr_check_status.py without requiring GitHub/network access.
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parents[1] / "tools" / "pr_check_status.py"
SPEC = importlib.util.spec_from_file_location("pr_check_status", MODULE_PATH)
assert SPEC and SPEC.loader
pr_check_status = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pr_check_status)


class PrCheckStatusTests(unittest.TestCase):
    def test_build_status_command_targets_exact_sha_and_stable_context(self) -> None:
        sha = "a" * 40
        command = pr_check_status.build_status_command(
            pr=97,
            sha=sha,
            state="success",
            stage="objective checks complete",
        )
        joined = " ".join(command)
        self.assertIn(f"statuses/{sha}", joined)
        self.assertIn("state=success", command)
        self.assertIn("context=brur-world/local-pr-check", command)
        self.assertIn("target_url=https://github.com/estecode/brur-world/pull/97", command)

    def test_build_status_command_rejects_unknown_state(self) -> None:
        with self.assertRaises(ValueError):
            pr_check_status.build_status_command(
                pr=97,
                sha="a" * 40,
                state="passed",
                stage="done",
            )

    @mock.patch.object(pr_check_status, "_run_gh")
    def test_resolve_pr_head_returns_exact_head_sha(self, run_gh: mock.Mock) -> None:
        sha = "b" * 40
        run_gh.return_value = '{"head":{"sha":"%s"}}' % sha
        self.assertEqual(pr_check_status.resolve_pr_head(98), sha)
        run_gh.assert_called_once_with(["api", "repos/estecode/brur-world/pulls/98"])

    @mock.patch.object(pr_check_status, "_run_gh")
    def test_record_status_posts_generated_command(self, run_gh: mock.Mock) -> None:
        sha = "c" * 40
        pr_check_status.record_status(pr=98, sha=sha, state="failure", stage="real-data")
        command = run_gh.call_args.args[0]
        self.assertIn("state=failure", command)
        self.assertIn("description=PR #98 local check failure: real-data", command)


if __name__ == "__main__":
    unittest.main()
