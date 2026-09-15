"""Tests persistent local PR-check status and execution context."""
from __future__ import annotations
import importlib.util
import os
from pathlib import Path
import unittest
from unittest import mock
MODULE_PATH = Path(__file__).resolve().parents[1] / "tools" / "pr_check_status.py"
SPEC = importlib.util.spec_from_file_location("pr_check_status", MODULE_PATH); assert SPEC and SPEC.loader
pr_check_status = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(pr_check_status)

class PrCheckStatusTests(unittest.TestCase):
    def test_build_status_command_targets_exact_sha_and_stable_context(self):
        sha="a"*40; command=pr_check_status.build_status_command(pr=97,sha=sha,state="success",stage="objective checks complete")
        self.assertIn(f"statuses/{sha}"," ".join(command)); self.assertIn("context=brur-world/local-pr-check",command)

    def test_build_status_command_rejects_unknown_state(self):
        with self.assertRaises(ValueError): pr_check_status.build_status_command(pr=97,sha="a"*40,state="passed",stage="done")

    @mock.patch.object(pr_check_status,"_run_gh")
    def test_resolve_pr_head_returns_exact_head_sha(self, run_gh):
        sha="b"*40; run_gh.return_value='{"head":{"sha":"%s","ref":"issue/98"}}'%sha
        self.assertEqual(pr_check_status.resolve_pr_head(98),sha)

    def test_context_body_contains_auditable_exact_execution_context(self):
        body=pr_check_status.build_context_body(pr=343,working_branch="issue/342-geodot-poc",main_sha="1"*40,target_branch="issue/342-geodot-poc",target_sha="2"*40,result="success")
        for expected in (pr_check_status.COMMENT_MARKER,"working_checkout_branch=issue/342-geodot-poc","safe_check_source=origin/main@"+"1"*40,"target_pr=343","target_head="+"2"*40,"result=success"): self.assertIn(expected,body)

    @mock.patch.object(pr_check_status,"_run_gh")
    def test_context_updates_existing_comment_in_place(self, run_gh):
        run_gh.side_effect=['[{"id":123,"body":"<!-- brur-world-safe-check-context --> old"}]','']
        pr_check_status.persist_context(pr=343,working_branch="main",main_sha="1"*40,target_branch="feature",target_sha="2"*40,result="failure")
        command=run_gh.call_args_list[1].args[0]; self.assertIn("PATCH",command); self.assertIn("repos/estecode/brur-world/issues/comments/123",command)

    @mock.patch.object(pr_check_status,"_run_gh")
    def test_context_creates_single_comment_when_missing(self, run_gh):
        run_gh.side_effect=['[]','']
        pr_check_status.persist_context(pr=343,working_branch="main",main_sha="1"*40,target_branch="feature",target_sha="2"*40,result="pending")
        self.assertIn("POST",run_gh.call_args_list[1].args[0])

    @mock.patch.object(pr_check_status,"persist_context")
    @mock.patch.object(pr_check_status,"resolve_pr")
    @mock.patch.object(pr_check_status,"_run_gh")
    def test_record_status_persists_tested_sha_even_if_pr_head_has_advanced(self, run_gh, resolve_pr, persist):
        tested="3"*40; resolve_pr.return_value={"sha":"4"*40,"branch":"feature"}
        with mock.patch.dict(os.environ,{"BRUR_PR_CHECK_WORKING_BRANCH":"stale-local","BRUR_PR_CHECK_MAIN_SHA":"5"*40},clear=False):
            pr_check_status.record_status(pr=343,sha=tested,state="success",stage="done")
        self.assertEqual(persist.call_args.kwargs["target_sha"],tested)
        self.assertEqual(persist.call_args.kwargs["target_branch"],"feature")

if __name__=="__main__": unittest.main()
