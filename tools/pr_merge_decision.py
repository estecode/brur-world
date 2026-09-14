#!/usr/bin/env python3
"""Parse the authoritative merge recommendation and manual CHECK from a BRUR PR body.

Dependencies: standard library only. Safe Check uses this persisted PR contract to decide
whether human inspection is required and, when it is, exactly what must be checked.
"""

from __future__ import annotations

import argparse
import sys


MARKER = "**Merge recommendation**"
ALLOWED = {
    "MERGE": "merge",
    "CHECK THEN MERGE": "check",
    "DO NOT MERGE": "block",
}


def _recommendation_index(lines: list[str]) -> tuple[int, str]:
    marker_indexes = [index for index, line in enumerate(lines) if line.strip() == MARKER]
    if len(marker_indexes) != 1:
        raise ValueError("PR body must contain exactly one merge recommendation marker")
    marker_index = marker_indexes[0]
    for index, line in enumerate(lines[marker_index + 1 :], start=marker_index + 1):
        stripped = line.strip()
        if not stripped:
            continue
        if stripped in ALLOWED:
            return index, ALLOWED[stripped]
        raise ValueError(f"invalid merge recommendation: {stripped}")
    raise ValueError("missing merge recommendation value")


def parse_merge_decision(body: str) -> str:
    return _recommendation_index(body.splitlines())[1]


def parse_manual_check(body: str) -> str:
    lines = body.splitlines()
    recommendation_index, decision = _recommendation_index(lines)
    if decision != "check":
        return ""
    for line in lines[recommendation_index + 1 :]:
        stripped = line.strip()
        if stripped.startswith("CHECK:"):
            check = stripped.removeprefix("CHECK:").strip()
            if not check:
                raise ValueError("CHECK THEN MERGE requires a concrete CHECK")
            return check
        if stripped.startswith("## "):
            break
    raise ValueError("CHECK THEN MERGE requires a concrete CHECK")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--field", choices=("decision", "check"), default="decision")
    args = parser.parse_args()
    body = sys.stdin.read()
    try:
        if args.field == "check":
            print(parse_manual_check(body))
        else:
            print(parse_merge_decision(body))
    except ValueError as exc:
        print(f"PR_CHECK=FAIL {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
