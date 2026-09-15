# Validates the repository agent-workflow contract and its regression fixtures.
# Depends only on Python stdlib plus root AGENTS.md and tests/agent_contract/cases.json.

from __future__ import annotations

import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
AGENTS = ROOT / "AGENTS.md"
CASES = Path(__file__).with_name("cases.json")

REQUIRED_AGENT_CONTRACT = {
    "response_before_action": "RESPONSE-BEFORE-ACTION GUARD",
    "running_is_invalid": "A response whose final state is `RUNNING` is **invalid by definition**.",
    "continue_not_narrate": "NEVER NARRATE CONTINUATION — EXECUTE IT",
    "targeted_first": "TARGETED VALIDATION\n-> INTEGRATION VALIDATION\n-> FINAL RELEVANT REGRESSION",
    "full_regression_not_debug_loop": "Run full relevant regression/CI on the stable final candidate, not as the ordinary debugging loop.",
    "human_terminal": "WAITING_FOR_HUMAN no agent-owned action remains",
    "done_terminal": "DONE              requested scope",
    "red_tests_agent_owned": "red tests",
    "safe_check_agent_owned": "objective Safe Check failure returns ownership to the agent",
    "missing_ci_not_handoff": "Missing hosted CI is not by itself `WAITING_FOR_HUMAN`",
    "safe_check_handoff_readiness": "SAFE CHECK HANDOFF READINESS GATE",
    "safe_check_exact_head": "exact PR head",
    "safe_check_objective_prerequisites": "agent-executable objective prerequisites",
}

REQUIRED_CASES = {
    "running_must_continue": "CONTINUE",
    "missing_ci_must_continue": "CONTINUE",
    "red_test_returns_to_agent": "CONTINUE",
    "safe_check_failure_returns_to_agent": "CONTINUE",
    "premature_safe_check_handoff": "CONTINUE",
    "targeted_before_full_regression": "TARGETED_VALIDATION",
    "genuine_human_handoff": "WAITING_FOR_HUMAN",
    "done_may_stop": "DONE",
}


def fail(name: str, detail: str) -> bool:
    print(f"FAIL  {name}: {detail}")
    return False


def passed(name: str) -> bool:
    print(f"PASS  {name}")
    return True


def main() -> int:
    ok = True
    agents = AGENTS.read_text(encoding="utf-8")
    payload = json.loads(CASES.read_text(encoding="utf-8"))

    print("Agent contract tests")
    for name, needle in REQUIRED_AGENT_CONTRACT.items():
        ok &= passed(f"contract:{name}") if needle in agents else fail(f"contract:{name}", f"missing {needle!r}")

    if payload.get("schema_version") != 1:
        ok &= fail("fixtures:schema_version", "expected schema_version 1")
        cases = []
    else:
        ok &= passed("fixtures:schema_version")
        cases = payload.get("cases", [])

    by_id = {}
    for case in cases:
        case_id = case.get("id")
        if not isinstance(case_id, str) or not case_id:
            ok &= fail("fixtures:case_id", "every case needs a non-empty id")
            continue
        if case_id in by_id:
            ok &= fail(f"fixture:{case_id}", "duplicate id")
            continue
        by_id[case_id] = case

    for case_id, expected in REQUIRED_CASES.items():
        case = by_id.get(case_id)
        if case is None:
            ok &= fail(f"fixture:{case_id}", "missing required regression case")
            continue
        if case.get("expected") != expected:
            ok &= fail(f"fixture:{case_id}", f"expected outcome must be {expected}")
            continue
        if not case.get("situation") or not isinstance(case.get("forbidden_terminal"), list):
            ok &= fail(f"fixture:{case_id}", "situation and forbidden_terminal are required")
            continue
        ok &= passed(f"fixture:{case_id}")

    extra = sorted(set(by_id) - set(REQUIRED_CASES))
    for case_id in extra:
        case = by_id[case_id]
        if not case.get("situation") or not case.get("expected") or not isinstance(case.get("forbidden_terminal"), list):
            ok &= fail(f"fixture:{case_id}", "invalid fixture schema")
        else:
            ok &= passed(f"fixture:{case_id}")

    total = len(REQUIRED_AGENT_CONTRACT) + 1 + len(by_id)
    print(f"\n{'PASS' if ok else 'FAIL'}: validated {total} contract checks/fixtures")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
