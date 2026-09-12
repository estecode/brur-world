#!/usr/bin/env bash
# Verifies PR-owned local checks run from the exact worktree, fail closed, and request visual review only when a subjective scope remains.
# Dependencies: bash, mktemp, grep, tools/run_pr_owned_check.sh, tools/pr_check.sh, tools/pr_check_local.sh, and tests/test_pr_check_entry.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/brur-pr-owned-check-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

WORKTREE="$TMP/worktree"
WORLD_DATA="$TMP/world_data"
mkdir -p "$WORKTREE/tools" "$WORLD_DATA"

output="$(bash "$ROOT/tools/run_pr_owned_check.sh" "$WORKTREE" 123 "$WORLD_DATA" /usr/bin/python3 /usr/bin/godot)"
grep -q 'PR_CHECK=SKIP_PR_OWNED_OBJECTIVE_CHECKS pr=123 reason=no-hook' <<<"$output"

cat > "$WORKTREE/tools/pr_check_local.sh" <<'HOOK'
set -euo pipefail
printf 'HOOK_PR=%s\n' "$BRUR_PR_CHECK_PR"
printf 'HOOK_WORKTREE=%s\n' "$BRUR_PR_CHECK_WORKTREE"
printf 'HOOK_WORLD_DATA=%s\n' "$BRUR_PR_CHECK_WORLD_DATA"
printf 'HOOK_PYTHON=%s\n' "$PYTHON_BIN"
printf 'HOOK_GODOT=%s\n' "$GODOT_BIN"
HOOK

output="$(bash "$ROOT/tools/run_pr_owned_check.sh" "$WORKTREE" 123 "$WORLD_DATA" /usr/bin/python3 /usr/bin/godot)"
grep -q 'PR_CHECK=RUN_PR_OWNED_OBJECTIVE_CHECKS pr=123 hook=tools/pr_check_local.sh' <<<"$output"
grep -q 'HOOK_PR=123' <<<"$output"
grep -Fq "HOOK_WORKTREE=$WORKTREE" <<<"$output"
grep -Fq "HOOK_WORLD_DATA=$WORLD_DATA" <<<"$output"
grep -q 'HOOK_PYTHON=/usr/bin/python3' <<<"$output"
grep -q 'HOOK_GODOT=/usr/bin/godot' <<<"$output"

cat > "$WORKTREE/tools/pr_check_local.sh" <<'HOOK'
exit 23
HOOK

set +e
bash "$ROOT/tools/run_pr_owned_check.sh" "$WORKTREE" 123 "$WORLD_DATA" /usr/bin/python3 /usr/bin/godot >/dev/null 2>&1
status=$?
set -e
[[ "$status" -eq 23 ]] || { printf 'expected hook failure 23, got %s\n' "$status" >&2; exit 1; }

hook_line="$(grep -n 'run_pr_owned_check.sh' "$ROOT/tools/pr_check.sh" | tail -n 1 | cut -d: -f1)"
success_line="$(grep -n -- '--state success' "$ROOT/tools/pr_check.sh" | head -n 1 | cut -d: -f1)"
[[ -n "$hook_line" && -n "$success_line" && "$hook_line" -lt "$success_line" ]] || {
  printf 'PR-owned hook must run before persistent success is recorded\n' >&2
  exit 1
}

no_prep_line="$(grep -n 'PR_CHECK=NO_EXPENSIVE_LOCAL_PREPARATION' "$ROOT/tools/pr_check_local.sh" | head -n 1 | cut -d: -f1)"
skip_visual_line="$(grep -n 'PR_CHECK=SKIP_VISUAL_REVIEW' "$ROOT/tools/pr_check_local.sh" | head -n 1 | cut -d: -f1)"
visual_line="$(grep -n 'PR_CHECK=VISUAL_REVIEW pr=' "$ROOT/tools/pr_check_local.sh" | head -n 1 | cut -d: -f1)"
[[ -n "$no_prep_line" && -n "$skip_visual_line" && -n "$visual_line" ]] || {
  printf 'Safe Check must expose both objective-only and visual-review paths\n' >&2
  exit 1
}
[[ "$no_prep_line" -lt "$skip_visual_line" && "$skip_visual_line" -lt "$visual_line" ]] || {
  printf 'objective-only completion must be decided before visual-review launch\n' >&2
  exit 1
}
if ! sed -n "${skip_visual_line},$((skip_visual_line + 3))p" "$ROOT/tools/pr_check_local.sh" | grep -Eq '^[[:space:]]*exit 0[[:space:]]*$'; then
  printf 'objective-only Safe Check must exit without launching Godot\n' >&2
  exit 1
fi

grep -q 'BUILDING_TILE_SCOPE.*required' "$ROOT/tools/pr_check_local.sh" || {
  printf 'visual presentation scopes must still be able to request review\n' >&2
  exit 1
}

bash "$ROOT/tests/test_pr_check_entry.sh"
printf 'pr-owned check hook tests passed\n'
