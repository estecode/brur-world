#!/usr/bin/env bash
# Runs one optional local objective-check hook owned by the exact PR worktree.
# Dependencies: bash plus explicit worktree/runtime paths supplied by tools/pr_check.sh.
set -euo pipefail

WORKTREE="${1:-}"
PR="${2:-}"
WORLD_DATA="${3:-}"
PYTHON_BIN="${4:-}"
GODOT_BIN="${5:-}"

[[ -d "$WORKTREE" ]] || { printf 'PR_CHECK=FAIL invalid PR worktree\n' >&2; exit 66; }
[[ "$PR" =~ ^[1-9][0-9]*$ ]] || { printf 'PR_CHECK=FAIL invalid PR number for PR-owned check\n' >&2; exit 64; }
[[ -d "$WORLD_DATA" ]] || { printf 'PR_CHECK=FAIL invalid world_data path for PR-owned check\n' >&2; exit 66; }
[[ -n "$PYTHON_BIN" ]] || { printf 'PR_CHECK=FAIL missing Python path for PR-owned check\n' >&2; exit 69; }
[[ -n "$GODOT_BIN" ]] || { printf 'PR_CHECK=FAIL missing Godot path for PR-owned check\n' >&2; exit 69; }

HOOK="$WORKTREE/tools/pr_check_local.sh"
if [[ ! -f "$HOOK" ]]; then
  printf 'PR_CHECK=SKIP_PR_OWNED_OBJECTIVE_CHECKS pr=%s reason=no-hook\n' "$PR"
  exit 0
fi

printf 'PR_CHECK=RUN_PR_OWNED_OBJECTIVE_CHECKS pr=%s hook=tools/pr_check_local.sh\n' "$PR"
(
  cd "$WORKTREE"
  BRUR_PR_CHECK_PR="$PR" \
  BRUR_PR_CHECK_WORKTREE="$WORKTREE" \
  BRUR_PR_CHECK_WORLD_DATA="$WORLD_DATA" \
  PYTHON_BIN="$PYTHON_BIN" \
  GODOT_BIN="$GODOT_BIN" \
  bash "$HOOK"
)
