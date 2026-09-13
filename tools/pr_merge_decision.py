#!/usr/bin/env python3
"""Parse the authoritative merge recommendation from a BRUR pull-request body.

Dependencies: standard library only. Used by the Safe Check entrypoint to decide whether a human runtime review is required.
"""

from __future__ import annotations

import sys


MARKER = "**Merge recommendation**"
ALLOWED = {
    "MERGE": "merge",
    "CHECK THEN MERGE": "check",
    "DO NOT MERGE": "block",
}


def parse_merge_decision(body: str) -> str:
    lines = body.splitlines()
    marker_indexes = [index for index, line in enumerate(lines) if line.strip() == MARKER]
    if len(marker_indexes) != 1:
        raise ValueError("PR body must contain exactly one merge recommendation marker")
    for line in lines[marker_indexes[0] + 1 :]:
        stripped = line.strip()
        if not stripped:
            continue
        if stripped in ALLOWED:
            return ALLOWED[stripped]
        raise ValueError(f"invalid merge recommendation: {stripped}")
    raise ValueError("missing merge recommendation value")


def main() -> int:
    try:
        print(parse_merge_decision(sys.stdin.read()))
    except ValueError as exc:
        print(f"PR_CHECK=FAIL {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
