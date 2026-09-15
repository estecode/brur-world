#!/usr/bin/env python3
"""Persist local PR-check state and execution context to GitHub.

Dependencies: standard library plus authenticated GitHub CLI.
"""
from __future__ import annotations

import argparse
import json
import subprocess

REPOSITORY = "estecode/brur-world"
STATUS_CONTEXT = "brur-world/local-pr-check"
COMMENT_MARKER = "<!-- brur-world-safe-check-context -->"
ALLOWED_STATES = {"pending", "success", "failure", "error"}


def _run_gh(args: list[str]) -> str:
    completed = subprocess.run(["gh", *args], check=True, capture_output=True, text=True)
    return completed.stdout.strip()


def resolve_pr(pr: int) -> dict[str, str]:
    payload = json.loads(_run_gh(["api", f"repos/{REPOSITORY}/pulls/{pr}"]))
    sha = str(payload["head"]["sha"]).strip()
    branch = str(payload["head"]["ref"]).strip()
    if len(sha) != 40 or not branch:
        raise RuntimeError("GitHub returned invalid PR head metadata")
    return {"sha": sha, "branch": branch}


def resolve_pr_head(pr: int) -> str:
    return resolve_pr(pr)["sha"]


def build_status_command(*, pr: int, sha: str, state: str, stage: str) -> list[str]:
    if state not in ALLOWED_STATES:
        raise ValueError(f"unsupported status state: {state}")
    clean_stage = " ".join(stage.strip().split()) or "unknown"
    description = f"PR #{pr} local check {state}: {clean_stage}"[:140]
    return ["api", "--method", "POST", f"repos/{REPOSITORY}/statuses/{sha}", "-f", f"state={state}", "-f", f"context={STATUS_CONTEXT}", "-f", f"description={description}", "-f", f"target_url=https://github.com/{REPOSITORY}/pull/{pr}"]


def record_status(*, pr: int, sha: str, state: str, stage: str) -> None:
    _run_gh(build_status_command(pr=pr, sha=sha, state=state, stage=stage))


def build_context_body(*, pr: int, working_branch: str, main_sha: str, target_branch: str, target_sha: str, result: str) -> str:
    if result not in ALLOWED_STATES:
        raise ValueError(f"unsupported context result: {result}")
    return "\n".join([
        COMMENT_MARKER,
        "### Safe Check execution context",
        "",
        "```text",
        f"working_checkout_branch={working_branch}",
        f"safe_check_source=origin/main@{main_sha}",
        f"target_pr={pr}",
        f"target_branch={target_branch}",
        f"target_head={target_sha}",
        f"result={result}",
        "```",
        "",
        "This comment is updated in place. `brur-world/local-pr-check` on the exact target SHA remains the authoritative merge gate.",
    ])


def persist_context(*, pr: int, working_branch: str, main_sha: str, target_branch: str, target_sha: str, result: str) -> None:
    body = build_context_body(pr=pr, working_branch=working_branch, main_sha=main_sha, target_branch=target_branch, target_sha=target_sha, result=result)
    comments = json.loads(_run_gh(["api", f"repos/{REPOSITORY}/issues/{pr}/comments", "--paginate"]) or "[]")
    existing = next((item for item in comments if COMMENT_MARKER in str(item.get("body", ""))), None)
    if existing:
        _run_gh(["api", "--method", "PATCH", f"repos/{REPOSITORY}/issues/comments/{existing['id']}", "-f", f"body={body}"])
    else:
        _run_gh(["api", "--method", "POST", f"repos/{REPOSITORY}/issues/{pr}/comments", "-f", f"body={body}"])


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    resolve_parser = subparsers.add_parser("resolve-head")
    resolve_parser.add_argument("--pr", type=int, required=True)
    meta_parser = subparsers.add_parser("resolve-metadata")
    meta_parser.add_argument("--pr", type=int, required=True)
    record_parser = subparsers.add_parser("record")
    record_parser.add_argument("--pr", type=int, required=True)
    record_parser.add_argument("--sha", required=True)
    record_parser.add_argument("--state", choices=sorted(ALLOWED_STATES), required=True)
    record_parser.add_argument("--stage", required=True)
    context_parser = subparsers.add_parser("context")
    context_parser.add_argument("--pr", type=int, required=True)
    context_parser.add_argument("--working-branch", required=True)
    context_parser.add_argument("--main-sha", required=True)
    context_parser.add_argument("--target-branch", required=True)
    context_parser.add_argument("--target-sha", required=True)
    context_parser.add_argument("--result", choices=sorted(ALLOWED_STATES), required=True)
    args = parser.parse_args()
    if args.command == "resolve-head":
        print(resolve_pr_head(args.pr))
    elif args.command == "resolve-metadata":
        print(json.dumps(resolve_pr(args.pr), sort_keys=True))
    elif args.command == "record":
        record_status(pr=args.pr, sha=args.sha, state=args.state, stage=args.stage)
    else:
        persist_context(pr=args.pr, working_branch=args.working_branch, main_sha=args.main_sha, target_branch=args.target_branch, target_sha=args.target_sha, result=args.result)


if __name__ == "__main__":
    main()
