#!/usr/bin/env python3
"""Persist local PR-check state to the exact GitHub PR head commit.

Dependencies:
- Standard library only.
- Uses the authenticated GitHub CLI as the project-local persistence adapter.
- Does not inspect Godot/world data or decide whether a PR is mergeable.
"""

from __future__ import annotations

import argparse
import json
import subprocess

REPOSITORY = "estecode/brur-world"
STATUS_CONTEXT = "brur-world/local-pr-check"
ALLOWED_STATES = {"pending", "success", "failure", "error"}


def _run_gh(args: list[str]) -> str:
    completed = subprocess.run(
        ["gh", *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout.strip()


def resolve_pr_head(pr: int) -> str:
    output = _run_gh(["api", f"repos/{REPOSITORY}/pulls/{pr}"])
    payload = json.loads(output)
    sha = str(payload["head"]["sha"]).strip()
    if len(sha) != 40:
        raise RuntimeError("GitHub returned an invalid PR head SHA")
    return sha


def build_status_command(*, pr: int, sha: str, state: str, stage: str) -> list[str]:
    if state not in ALLOWED_STATES:
        raise ValueError(f"unsupported status state: {state}")
    clean_stage = " ".join(stage.strip().split()) or "unknown"
    description = f"PR #{pr} local check {state}: {clean_stage}"[:140]
    return [
        "api",
        "--method",
        "POST",
        f"repos/{REPOSITORY}/statuses/{sha}",
        "-f",
        f"state={state}",
        "-f",
        f"context={STATUS_CONTEXT}",
        "-f",
        f"description={description}",
        "-f",
        f"target_url=https://github.com/{REPOSITORY}/pull/{pr}",
    ]


def record_status(*, pr: int, sha: str, state: str, stage: str) -> None:
    _run_gh(build_status_command(pr=pr, sha=sha, state=state, stage=stage))


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    resolve_parser = subparsers.add_parser("resolve-head")
    resolve_parser.add_argument("--pr", type=int, required=True)

    record_parser = subparsers.add_parser("record")
    record_parser.add_argument("--pr", type=int, required=True)
    record_parser.add_argument("--sha", required=True)
    record_parser.add_argument("--state", choices=sorted(ALLOWED_STATES), required=True)
    record_parser.add_argument("--stage", required=True)

    args = parser.parse_args()
    if args.command == "resolve-head":
        print(resolve_pr_head(args.pr))
    else:
        record_status(pr=args.pr, sha=args.sha, state=args.state, stage=args.stage)


if __name__ == "__main__":
    main()
