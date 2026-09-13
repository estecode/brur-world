#!/usr/bin/env python3
"""Regression tests for native GPS source selection in local PR checks.

Dependencies:
- Executes the pure tools/pr_check_native_gps_policy.sh decision helper.
- Verifies pr_check.sh keeps exact-PR builds separate from current-main fallback builds.
"""

from __future__ import annotations

import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / "tools" / "pr_check_native_gps_policy.sh"
PR_CHECK = ROOT / "tools" / "pr_check.sh"


def decide(scope: str, reusable: str) -> str:
    result = subprocess.run(
        ["bash", str(POLICY), scope, reusable],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def main() -> None:
    assert decide("required", "yes") == "pr"
    assert decide("required", "no") == "pr"
    assert decide("skip", "yes") == "reuse"
    assert decide("skip", "no") == "main"

    invalid = subprocess.run(
        ["bash", str(POLICY), "skip", "maybe"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert invalid.returncode != 0

    script = PR_CHECK.read_text(encoding="utf-8")
    assert 'bash "$TMP/tools/build_native_gps.sh"' in script, (
        "native-GPS-changing PRs must build the exact PR checkout"
    )
    assert 'worktree add --quiet --detach "$NATIVE_MAIN_TMP" "$MAIN_HEAD"' in script, (
        "unrelated PR fallback must use an exact current-main worktree"
    )
    assert 'bash "$NATIVE_MAIN_TMP/tools/build_native_gps.sh"' in script, (
        "missing unrelated binaries must be built by current-main tooling"
    )
    assert 'ln -s "$NATIVE_MAIN_TMP/bin" "$TMP/bin"' in script, (
        "current-main binaries must be exposed to the exact PR checkout"
    )
    assert 'source=current-main revision=%s' in script
    assert 'source=pr revision=%s' in script

    print("PR check native GPS source tests: OK")


if __name__ == "__main__":
    main()
